const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { initializeApp } = require("firebase-admin/app");

initializeApp();
setGlobalOptions({ region: "asia-southeast1", maxInstances: 20, concurrency: 80 });

const db = getFirestore();
const ROOM_SIZES = new Set([8, 12]);
const PHASE_SECONDS = 30;

// Monetization is deliberately disabled during testing.
// When production billing is enabled, payments must be verified server-side
// before tokens or paid gifts are credited.
const ECONOMY_TEST_MODE = true;
const CURRENCY = "UZS";

function phaseDeadline() {
  return Date.now() + PHASE_SECONDS * 1000;
}

function authUid(request) {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");
  return request.auth.uid;
}

function cleanName(value) {
  const name = String(value ?? "").trim().replace(/\s+/g, " ");
  if (name.length < 2 || name.length > 20) {
    throw new HttpsError("invalid-argument", "Name must be 2-20 characters.");
  }
  return name;
}

function cleanRoomId(value) {
  const id = String(value ?? "").trim().toUpperCase();
  if (!/^[A-Z0-9]{6}$/.test(id)) {
    throw new HttpsError("invalid-argument", "Invalid room code.");
  }
  return id;
}

function mafiaCount(size) {
  return Math.max(1, Math.floor(size / 4));
}

function shuffledRoles(size) {
  const roles = [...Array(mafiaCount(size)).fill("mafia"), "doctor", "sheriff"];
  while (roles.length < size) roles.push("citizen");
  for (let i = roles.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [roles[i], roles[j]] = [roles[j], roles[i]];
  }
  return roles;
}

function randomRoomId() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  return Array.from({ length: 6 }, () => alphabet[Math.floor(Math.random() * alphabet.length)]).join("");
}

async function requireMember(roomId, uid) {
  const snap = await db.doc(`rooms/${roomId}/players/${uid}`).get();
  if (!snap.exists) throw new HttpsError("permission-denied", "You are not a member of this room.");
  return snap.data();
}

async function getRoomAndPlayers(roomId) {
  const roomRef = db.doc(`rooms/${roomId}`);
  const roomSnap = await roomRef.get();
  if (!roomSnap.exists) throw new HttpsError("not-found", "Room not found.");
  const playersSnap = await roomRef.collection("players").get();
  return { roomRef, room: roomSnap.data(), players: playersSnap.docs };
}

function winnerFor(players) {
  const alive = players.filter(p => p.alive);
  const mafia = alive.filter(p => p.role === "mafia").length;
  const others = alive.length - mafia;
  if (mafia === 0) return "citizen";
  if (mafia >= others) return "mafia";
  return null;
}


async function ensureUserProfile(uid, name) {
  const ref = db.doc(`users/${uid}`);
  const snap = await ref.get();
  if (!snap.exists) {
    await ref.set({
      uid,
      name,
      language: "uz",
      avatar: null,
      coins: 0,
      xp: 0,
      level: 1,
      stats: {
        games: 0,
        wins: 0,
        losses: 0,
        mafiaWins: 0,
        citizenWins: 0,
        doctorWins: 0,
        sheriffWins: 0,
        kills: 0,
        saves: 0,
        checks: 0,
        votes: 0,
        giftsSent: 0,
        giftsReceived: 0,
      },
      wallet: {
        tokens: 0,
        lifetimePurchasedTokens: 0,
        lifetimeSpentTokens: 0,
      },
      settings: { sound: true, notifications: true },
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  } else {
    await ref.set({ name, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  }
}

function gameHistoryData(room, roomId) {
  return {
    gameId: roomId,
    roomId,
    size: room.size,
    round: Number(room.round || 0),
    winner: room.winner || null,
    startedAt: room.startedAt || null,
    finishedAt: FieldValue.serverTimestamp(),
  };
}

async function finalizeGame(tx, roomRef, room, players, winner, roles = new Map()) {
  const gameRef = db.collection("gameSessions").doc(room.roomId);
  tx.set(gameRef, {
    ...gameHistoryData({ ...room, winner }, room.roomId),
    status: "finished",
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  for (const p of players) {
    const uid = p.id;
    const player = p.data();
    const profileRef = db.doc(`users/${uid}`);
    const historyRef = profileRef.collection("games").doc(room.roomId);
    const role = roles.get(uid) || player.role || null;
    const win = (winner === "mafia" && role === "mafia") ||
      (winner === "citizen" && role !== "mafia");

    tx.set(profileRef, {
      uid,
      name: player.name || uid,
      stats: {
        games: FieldValue.increment(1),
        wins: FieldValue.increment(win ? 1 : 0),
        losses: FieldValue.increment(win ? 0 : 1),
        mafiaWins: FieldValue.increment(win && role === "mafia" ? 1 : 0),
        citizenWins: FieldValue.increment(win && role === "citizen" ? 1 : 0),
        doctorWins: FieldValue.increment(win && role === "doctor" ? 1 : 0),
        sheriffWins: FieldValue.increment(win && role === "sheriff" ? 1 : 0),
      },
      xp: FieldValue.increment(win ? 100 : 25),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    tx.set(historyRef, {
      ...gameHistoryData({ ...room, winner }, room.roomId),
      playerName: player.name || uid,
      role,
      won: win,
      alive: player.alive !== false,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }
}

exports.createRoom = onCall(async request => {
  const uid = authUid(request);
  const size = Number(request.data?.size);
  const name = cleanName(request.data?.name);
  if (!ROOM_SIZES.has(size)) throw new HttpsError("invalid-argument", "Room size must be 8 or 12.");

  for (let attempt = 0; attempt < 5; attempt++) {
    const roomId = randomRoomId();
    const roomRef = db.doc(`rooms/${roomId}`);
    try {
      await db.runTransaction(async tx => {
        if ((await tx.get(roomRef)).exists) throw new Error("collision");
        tx.create(roomRef, {
          roomId, size, hostUid: uid, phase: "lobby", round: 0, winner: null,
          createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()
        });
        tx.create(roomRef.collection("players").doc(uid), {
          uid, name, seat: 0, alive: true, joinedAt: FieldValue.serverTimestamp()
        });
      });
      await ensureUserProfile(uid, name);
      await db.collection("gameSessions").doc(roomId).set({
        gameId: roomId,
        roomId,
        size,
        status: "lobby",
        phase: "lobby",
        round: 0,
        winner: null,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      return { roomId, size, host: true };
    } catch (e) {
      if (e.message !== "collision") throw e;
    }
  }
  throw new HttpsError("aborted", "Could not allocate a room.");
});

exports.joinRoom = onCall(async request => {
  const uid = authUid(request);
  const roomId = cleanRoomId(request.data?.roomId);
  const name = cleanName(request.data?.name);
  const roomRef = db.doc(`rooms/${roomId}`);
  const playerRef = roomRef.collection("players").doc(uid);

  await db.runTransaction(async tx => {
    const roomSnap = await tx.get(roomRef);
    if (!roomSnap.exists) throw new HttpsError("not-found", "Room not found.");
    const room = roomSnap.data();
    if (room.phase !== "lobby") throw new HttpsError("failed-precondition", "Game has already started.");
    const players = await tx.get(roomRef.collection("players"));
    if (players.docs.some(d => d.id === uid)) {
      tx.update(playerRef, { name, updatedAt: FieldValue.serverTimestamp() });
      return;
    }
    if (players.size >= room.size) throw new HttpsError("resource-exhausted", "Room is full.");
    const usedSeats = new Set(players.docs.map(d => Number(d.data().seat)).filter(Number.isFinite));
    let seat = 0;
    while (usedSeats.has(seat)) seat++;
    tx.create(playerRef, {
      uid, name, seat, alive: true, joinedAt: FieldValue.serverTimestamp()
    });
    tx.update(roomRef, { updatedAt: FieldValue.serverTimestamp() });
  });

  const room = (await roomRef.get()).data();
  await ensureUserProfile(uid, name);
  return { roomId, size: room.size, host: room.hostUid === uid };
});

exports.leaveRoom = onCall(async request => {
  const uid = authUid(request);
  const roomId = cleanRoomId(request.data?.roomId);
  const roomRef = db.doc(`rooms/${roomId}`);
  const playerRef = roomRef.collection("players").doc(uid);
  await db.runTransaction(async tx => {
    const room = await tx.get(roomRef);
    const player = await tx.get(playerRef);
    if (!room.exists || !player.exists) return;
    if (room.data().phase !== "lobby") {
      throw new HttpsError("failed-precondition", "Cannot leave after game start.");
    }
    const current = room.data();
    const players = await tx.get(roomRef.collection("players"));
    const remaining = players.docs.filter(d => d.id !== uid);
    tx.delete(playerRef);
    if (current.hostUid === uid) {
      if (remaining.length === 0) {
        tx.delete(roomRef);
        return;
      }
      remaining.sort((a, b) => Number(a.data().seat) - Number(b.data().seat));
      tx.update(roomRef, {
        hostUid: remaining[0].id,
        updatedAt: FieldValue.serverTimestamp()
      });
    } else {
      tx.update(roomRef, { updatedAt: FieldValue.serverTimestamp() });
    }
  });
  return { ok: true };
});

exports.startGame = onCall(async request => {
  const uid = authUid(request);
  const roomId = cleanRoomId(request.data?.roomId);
  const roomRef = db.doc(`rooms/${roomId}`);

  await db.runTransaction(async tx => {
    const roomSnap = await tx.get(roomRef);
    if (!roomSnap.exists) throw new HttpsError("not-found", "Room not found.");
    const room = roomSnap.data();
    if (room.hostUid !== uid) throw new HttpsError("permission-denied", "Only the host can start.");
    if (room.phase !== "lobby") throw new HttpsError("failed-precondition", "Game already started.");
    const playersSnap = await tx.get(roomRef.collection("players"));
    if (playersSnap.size !== room.size) throw new HttpsError("failed-precondition", "Room must be full before starting.");

    const roles = shuffledRoles(room.size);
    playersSnap.docs.sort((a, b) => Number(a.data().seat) - Number(b.data().seat)).forEach((doc, index) => {
      tx.set(roomRef.collection("private").doc(doc.id), {
        uid: doc.id, role: roles[index], round: 1, updatedAt: FieldValue.serverTimestamp()
      });
      tx.update(doc.ref, { alive: true, rolePublic: roles[index] === "citizen" ? "citizen" : "special" });
    });
    tx.update(roomRef, {
      phase: "night",
      round: 1,
      winner: null,
      status: "active",
      startedAt: FieldValue.serverTimestamp(),
      phaseEndsAt: phaseDeadline(),
      updatedAt: FieldValue.serverTimestamp()
    });
    tx.set(db.collection("gameSessions").doc(roomId), {
      gameId: roomId,
      roomId,
      size: room.size,
      status: "active",
      phase: "night",
      round: 1,
      winner: null,
      hostUid: room.hostUid,
      startedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  return { ok: true, phase: "night" };
});

exports.getMyRole = onCall(async request => {
  const uid = authUid(request);
  const roomId = cleanRoomId(request.data?.roomId);
  await requireMember(roomId, uid);
  const snap = await db.doc(`rooms/${roomId}/private/${uid}`).get();
  if (!snap.exists) throw new HttpsError("failed-precondition", "Game has not started.");
  return { role: snap.data().role, round: snap.data().round, checkResult: snap.data().checkResult ?? null };
});

exports.submitAction = onCall(async request => {
  const uid = authUid(request);
  const roomId = cleanRoomId(request.data?.roomId);
  const type = String(request.data?.type ?? "");
  const targetUid = String(request.data?.targetUid ?? "");
  if (!["kill", "save", "check", "vote"].includes(type) || !targetUid) {
    throw new HttpsError("invalid-argument", "Invalid action.");
  }

  const roomRef = db.doc(`rooms/${roomId}`);
  await requireMember(roomId, uid);
  await db.runTransaction(async tx => {
    const roomSnap = await tx.get(roomRef);
    if (!roomSnap.exists) throw new HttpsError("not-found", "Room not found.");
    const room = roomSnap.data();
    const actorRef = roomRef.collection("private").doc(uid);
    const actorPlayerRef = roomRef.collection("players").doc(uid);
    const targetRef = roomRef.collection("players").doc(targetUid);
    const actor = await tx.get(actorRef);
    const actorPlayer = await tx.get(actorPlayerRef);
    const target = await tx.get(targetRef);
    if (!actor.exists || !actorPlayer.exists || !target.exists) {
      throw new HttpsError("not-found", "Game data not found.");
    }
    if (!actorPlayer.data().alive) {
      throw new HttpsError("failed-precondition", "Dead players cannot act.");
    }
    if (!target.data().alive) throw new HttpsError("failed-precondition", "Target is dead.");

    const role = actor.data().role;
    const allowed = {
      kill: room.phase === "night" && role === "mafia",
      save: room.phase === "night" && role === "doctor",
      check: room.phase === "night" && role === "sheriff",
      vote: room.phase === "vote"
    };
    if (!allowed[type]) throw new HttpsError("failed-precondition", "Action is not allowed now.");
    if (targetUid === uid && type !== "save") {
      throw new HttpsError("invalid-argument", "Self-targeting is not allowed.");
    }

    const actionRef = roomRef.collection("events").doc(`${type}_${uid}_${room.round}`);
    tx.set(actionRef, {
      type, actorUid: uid, targetUid, round: room.round, createdAt: FieldValue.serverTimestamp()
    }, { merge: true });
  });
  return { ok: true };
});

exports.resolveNight = onCall(async request => {
  const uid = authUid(request), roomId = cleanRoomId(request.data?.roomId);
  await requireMember(roomId, uid);
  const roomRef = db.doc(`rooms/${roomId}`);
  return db.runTransaction(async tx => {
    const roomSnap = await tx.get(roomRef);
    if (!roomSnap.exists) throw new HttpsError("not-found", "Room not found.");
    const room = roomSnap.data();
    if (room.phase !== "night") throw new HttpsError("failed-precondition", "Not a night phase.");
    if (Number(room.phaseEndsAt || 0) > Date.now()) {
      throw new HttpsError("failed-precondition", "Night timer has not expired.");
    }
    const players = (await tx.get(roomRef.collection("players"))).docs;
    const alivePlayers = players.filter(d => d.data().alive);
    const events = (await tx.get(roomRef.collection("events").where("round", "==", room.round))).docs.map(d => d.data());
    const privateRefs = alivePlayers.map(d => roomRef.collection("private").doc(d.id));
    const privateDocs = privateRefs.length ? await tx.getAll(...privateRefs) : [];
    const roles = new Map(privateDocs.filter(d => d.exists).map(d => [d.id, d.data().role]));
    const aliveIds = new Set(alivePlayers.map(d => d.id));
    const kills = events.filter(e => e.type === "kill" && roles.get(e.actorUid) === "mafia" && aliveIds.has(e.actorUid) && aliveIds.has(e.targetUid));
    const saves = events.filter(e => e.type === "save" && roles.get(e.actorUid) === "doctor" && aliveIds.has(e.actorUid) && aliveIds.has(e.targetUid));
    const checks = events.filter(e => e.type === "check" && roles.get(e.actorUid) === "sheriff" && aliveIds.has(e.actorUid) && aliveIds.has(e.targetUid));
    const killCounts = new Map();
    for (const e of kills) killCounts.set(e.targetUid, (killCounts.get(e.targetUid) || 0) + 1);
    const maxKills = Math.max(0, ...killCounts.values());
    const leaders = [...killCounts.entries()].filter(([, n]) => n === maxKills && n > 0);
    const killTarget = leaders.length === 1 ? leaders[0][0] : null;
    const saveTarget = saves.length ? saves[saves.length - 1].targetUid : null;
    const eliminated = Boolean(killTarget && killTarget !== saveTarget);
    const after = players.map(d => ({uid:d.id,...d.data(),role:roles.get(d.id),alive:d.id===killTarget&&eliminated?false:d.data().alive}));
    const winner = winnerFor(after);
    if (eliminated) tx.update(roomRef.collection("players").doc(killTarget), {alive:false});
    for (const e of checks) tx.set(roomRef.collection("private").doc(e.actorUid), {checkResult:roles.get(e.targetUid)==="mafia",round:room.round,updatedAt:FieldValue.serverTimestamp()},{merge:true});
    tx.update(roomRef, {
      phase: winner ? "finished" : "talk",
      status: winner ? "finished" : "active",
      winner,
      phaseEndsAt: winner ? null : phaseDeadline(),
      updatedAt: FieldValue.serverTimestamp()
    });
    if (winner) await finalizeGame(tx, roomRef, room, players, winner, roles);
    tx.set(db.collection("gameSessions").doc(roomId), {
      phase: winner ? "finished" : "talk",
      status: winner ? "finished" : "active",
      winner,
      round: room.round,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return {ok:true,phase:winner?"finished":"talk",winner,killed:eliminated?killTarget:null};
  });
});

exports.startVote = onCall(async request => {
  const uid = authUid(request);
  const roomId = cleanRoomId(request.data?.roomId);
  await requireMember(roomId, uid);
  const roomRef = db.doc(`rooms/${roomId}`);
  await db.runTransaction(async tx => {
    const snap = await tx.get(roomRef);
    if (!snap.exists) throw new HttpsError("not-found", "Room not found.");
    const room = snap.data();
    if (room.phase !== "talk") throw new HttpsError("failed-precondition", "Not a talk phase.");
    if (Number(room.phaseEndsAt || 0) > Date.now()) {
      throw new HttpsError("failed-precondition", "Discussion timer has not expired.");
    }
    tx.update(roomRef, {
      phase: "vote",
      phaseEndsAt: phaseDeadline(),
      updatedAt: FieldValue.serverTimestamp()
    });
  });
  return { ok: true, phase: "vote" };
});

exports.resolveVote = onCall(async request => {
  const uid = authUid(request), roomId = cleanRoomId(request.data?.roomId);
  await requireMember(roomId, uid);
  const roomRef = db.doc(`rooms/${roomId}`);
  return db.runTransaction(async tx => {
    const roomSnap = await tx.get(roomRef);
    if (!roomSnap.exists) throw new HttpsError("not-found", "Room not found.");
    const room = roomSnap.data();
    if (room.phase !== "vote") throw new HttpsError("failed-precondition", "Not a vote phase.");
    if (Number(room.phaseEndsAt || 0) > Date.now()) {
      throw new HttpsError("failed-precondition", "Voting timer has not expired.");
    }
    const players = (await tx.get(roomRef.collection("players"))).docs;
    const privateRefs = players.map(d => roomRef.collection("private").doc(d.id));
    const privateDocs = privateRefs.length ? await tx.getAll(...privateRefs) : [];
    const roles = new Map(privateDocs.filter(d => d.exists).map(d => [d.id, d.data().role]));
    const alive = new Set(players.filter(d => d.data().alive).map(d => d.id));
    const events = (await tx.get(roomRef.collection("events").where("round","==",room.round))).docs;
    const counts = new Map();
    for (const d of events) { const e=d.data(); if(e.type==="vote"&&alive.has(e.actorUid)&&alive.has(e.targetUid)&&e.actorUid!==e.targetUid) counts.set(e.targetUid,(counts.get(e.targetUid)||0)+1); }
    const maxVotes=Math.max(0,...counts.values());
    const leaders=[...counts.entries()].filter(([,n])=>n===maxVotes&&n>0);
    const eliminated=leaders.length===1?leaders[0][0]:null;
    const after=players.map(d=>({uid:d.id,...d.data(),role:roles.get(d.id),alive:d.id===eliminated?false:d.data().alive}));
    const winner=winnerFor(after);
    if(eliminated) tx.update(roomRef.collection("players").doc(eliminated),{alive:false});
    if(!winner) for(const p of players) tx.set(roomRef.collection("private").doc(p.id),{round:room.round+1,checkResult:FieldValue.delete(),updatedAt:FieldValue.serverTimestamp()},{merge:true});
    tx.update(roomRef, {
      phase: winner ? "finished" : "night",
      status: winner ? "finished" : "active",
      winner,
      round: winner ? room.round : room.round + 1,
      phaseEndsAt: winner ? null : phaseDeadline(),
      updatedAt: FieldValue.serverTimestamp()
    });
    if (winner) await finalizeGame(tx, roomRef, room, players, winner);
    tx.set(db.collection("gameSessions").doc(roomId), {
      phase: winner ? "finished" : "night",
      status: winner ? "finished" : "active",
      winner,
      round: winner ? room.round : room.round + 1,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return {ok:true,phase:winner?"finished":"night",winner,eliminated};
  });
});



exports.updateProfile = onCall(async request => {
  const uid = authUid(request);
  const name = cleanName(request.data?.name);
  const language = String(request.data?.language ?? "uz");
  if (!["uz", "ru", "en"].includes(language)) {
    throw new HttpsError("invalid-argument", "Unsupported language.");
  }
  await ensureUserProfile(uid, name);
  await db.doc(`users/${uid}`).set({
    name,
    language,
    avatar: request.data?.avatar ?? null,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true };
});

exports.sendMessage = onCall(async request => {
  const uid = authUid(request);
  const roomId = cleanRoomId(request.data?.roomId);
  const text = String(request.data?.text ?? "").trim();
  if (!text || text.length > 500) {
    throw new HttpsError("invalid-argument", "Message must be 1-500 characters.");
  }
  const roomRef = db.doc(`rooms/${roomId}`);
  const playerRef = roomRef.collection("players").doc(uid);
  const player = await playerRef.get();
  if (!player.exists) throw new HttpsError("permission-denied", "You are not in this room.");
  await roomRef.collection("messages").add({
    senderUid: uid,
    senderName: player.data().name,
    text,
    round: 0,
    createdAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

exports.getMyStats = onCall(async request => {
  const uid = authUid(request);
  const snap = await db.doc(`users/${uid}`).get();
  if (!snap.exists) await ensureUserProfile(uid, "O'yinchi");
  const profile = (await db.doc(`users/${uid}`).get()).data();
  return { profile };
});

const GIFT_CATALOG = [
  { id: "rose", emoji: "🌹", name: "Atirgul", priceSom: 100 },
  { id: "mystery", emoji: "🎁", name: "Sirli sovg'a", priceSom: 200 },
  { id: "heart", emoji: "❤️", name: "Yurak", priceSom: 300 },
  { id: "chocolate", emoji: "🍫", name: "Shokolad", priceSom: 500 },
  { id: "cake", emoji: "🎂", name: "Tort", priceSom: 1000 },
  { id: "teddy", emoji: "🧸", name: "Ayiqcha", priceSom: 2000 },
  { id: "diamond", emoji: "💎", name: "Olmos", priceSom: 5000 },
  { id: "crown", emoji: "👑", name: "Toj", priceSom: 10000 },
];

const TOKEN_PACKS = [
  { id: "tokens_100", tokens: 100, priceSom: 1000 },
  { id: "tokens_550", tokens: 550, priceSom: 5000 },
  { id: "tokens_1200", tokens: 1200, priceSom: 10000 },
  { id: "tokens_6500", tokens: 6500, priceSom: 50000 },
];

const ROLE_CATALOG = [
  { id: "mafia", name: "Mafiya", tokenCost: 0, selectable: false },
  { id: "doctor", name: "Doktor", tokenCost: 0, selectable: false },
  { id: "sheriff", name: "Komissar", tokenCost: 0, selectable: false },
  { id: "citizen", name: "Tinch aholi", tokenCost: 0, selectable: false },
];

exports.getGiftCatalog = onCall(async request => {
  authUid(request);
  const ref = db.collection("giftCatalog");
  const snap = await ref.get();

  if (snap.empty) {
    const batch = db.batch();
    for (const gift of GIFT_CATALOG) {
      batch.set(ref.doc(gift.id), {
        ...gift,
        currency: CURRENCY,
        active: true,
        testFree: ECONOMY_TEST_MODE,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return {
      testMode: ECONOMY_TEST_MODE,
      currency: CURRENCY,
      gifts: GIFT_CATALOG.map(g => ({
        ...g, currency: CURRENCY, active: true, testFree: ECONOMY_TEST_MODE
      })),
    };
  }

  return {
    testMode: ECONOMY_TEST_MODE,
    currency: CURRENCY,
    gifts: snap.docs
      .map(d => d.data())
      .filter(g => g.active !== false)
      .sort((a, b) => Number(a.priceSom || 0) - Number(b.priceSom || 0)),
  };
});

exports.getEconomyCatalog = onCall(async request => {
  authUid(request);
  return {
    testMode: ECONOMY_TEST_MODE,
    currency: CURRENCY,
    gifts: GIFT_CATALOG,
    tokenPacks: TOKEN_PACKS,
    roles: ROLE_CATALOG,
    note: "Real-money purchases are disabled until production billing verification is enabled.",
  };
});

exports.sendGift = onCall(async request => {
  const uid = authUid(request);
  const roomId = cleanRoomId(request.data?.roomId);
  const recipientUid = String(request.data?.recipientUid ?? "").trim();
  const giftId = String(request.data?.giftId ?? "").trim();

  if (!recipientUid || recipientUid === uid) {
    throw new HttpsError("invalid-argument", "Choose another player.");
  }
  if (!giftId) {
    throw new HttpsError("invalid-argument", "Gift is required.");
  }

  const roomRef = db.doc(`rooms/${roomId}`);
  const senderRef = roomRef.collection("players").doc(uid);
  const recipientRef = roomRef.collection("players").doc(recipientUid);
  const giftRef = db.collection("giftCatalog").doc(giftId);

  await db.runTransaction(async tx => {
    const [roomSnap, senderSnap, recipientSnap, giftSnap] = await Promise.all([
      tx.get(roomRef),
      tx.get(senderRef),
      tx.get(recipientRef),
      tx.get(giftRef),
    ]);

    if (!roomSnap.exists || !senderSnap.exists || !recipientSnap.exists) {
      throw new HttpsError("not-found", "Player or room not found.");
    }
    if (!giftSnap.exists || giftSnap.data().active === false) {
      throw new HttpsError("not-found", "Gift not found.");
    }

    const gift = giftSnap.data();
    const priceSom = Number(gift.priceSom || 0);

    tx.create(roomRef.collection("gifts").doc(), {
      senderUid: uid,
      senderName: senderSnap.data().name,
      recipientUid,
      recipientName: recipientSnap.data().name,
      giftId,
      gift,
      priceSom,
      currency: CURRENCY,
      paymentStatus: ECONOMY_TEST_MODE ? "test_free" : "verified",
      projectRevenueSom: ECONOMY_TEST_MODE ? 0 : priceSom,
      round: Number(roomSnap.data().round || 0),
      createdAt: FieldValue.serverTimestamp(),
    });

    tx.set(db.doc(`users/${uid}`), {
      stats: { giftsSent: FieldValue.increment(1) },
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    tx.set(db.doc(`users/${recipientUid}`), {
      stats: { giftsReceived: FieldValue.increment(1) },
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });

  return {
    ok: true,
    testMode: ECONOMY_TEST_MODE,
    chargedSom: 0,
    listedPriceSom: Number((await giftRef.get()).data()?.priceSom || 0),
  };
});
