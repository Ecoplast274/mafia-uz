const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { initializeApp } = require("firebase-admin/app");

initializeApp();
setGlobalOptions({ region: "asia-southeast1", maxInstances: 20, concurrency: 80 });

const db = getFirestore();
const ROOM_SIZES = new Set([8, 12]);

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
    tx.update(roomRef, { phase: "night", round: 1, winner: null, updatedAt: FieldValue.serverTimestamp() });
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
  const uid = authUid(request);
  const roomId = cleanRoomId(request.data?.roomId);
  await requireMember(roomId, uid);

  const roomRef = db.doc(`rooms/${roomId}`);
  const roomSnap = await roomRef.get();
  if (!roomSnap.exists) throw new HttpsError("not-found", "Room not found.");
  const room = roomSnap.data();
  if (room.hostUid !== uid) {
    throw new HttpsError("permission-denied", "Only the host can resolve the night.");
  }
  if (room.phase !== "night") {
    throw new HttpsError("failed-precondition", "Not a night phase.");
  }
  const players = (await roomRef.collection("players").get()).docs;
  const alivePlayers = players.filter(d => d.data().alive);
  const eventsSnap = await roomRef.collection("events").where("round", "==", room.round).get();
  const events = eventsSnap.docs.map(d => d.data());

  const privateDocs = await Promise.all(alivePlayers.map(d => roomRef.collection("private").doc(d.id).get()));
  const roleByUid = new Map(privateDocs.filter(d => d.exists).map(d => [d.id, d.data().role]));
  const aliveIds = new Set(alivePlayers.map(d => d.id));

  const kills = events.filter(e => e.type === "kill" && roleByUid.get(e.actorUid) === "mafia" && aliveIds.has(e.actorUid) && aliveIds.has(e.targetUid));
  const saves = events.filter(e => e.type === "save" && roleByUid.get(e.actorUid) === "doctor" && aliveIds.has(e.actorUid) && aliveIds.has(e.targetUid));
  const checks = events.filter(e => e.type === "check" && roleByUid.get(e.actorUid) === "sheriff" && aliveIds.has(e.actorUid) && aliveIds.has(e.targetUid));

  const killCounts = new Map();
  for (const e of kills) killCounts.set(e.targetUid, (killCounts.get(e.targetUid) || 0) + 1);
  const maxKills = Math.max(0, ...killCounts.values());
  const killLeaders = [...killCounts.entries()].filter(([, n]) => n === maxKills && n > 0);
  const killTarget = killLeaders.length === 1 ? killLeaders[0][0] : null;
  const saveTarget = saves.length ? saves[saves.length - 1].targetUid : null;

  const updates = [];
  let winner = null;
  if (killTarget && killTarget !== saveTarget) {
    updates.push({ ref: roomRef.collection("players").doc(killTarget), data: { alive: false } });
  }

  const playerStates = players.map(d => ({ uid: d.id, ...d.data(), role: roleByUid.get(d.id) }));
  const nextStates = playerStates.map(p => p.uid === killTarget && killTarget !== saveTarget ? { ...p, alive: false } : p);
  winner = winnerFor(nextStates);

  await db.runTransaction(async tx => {
    const currentSnap = await tx.get(roomRef);
    if (!currentSnap.exists) throw new HttpsError("not-found", "Room not found.");
    const current = currentSnap.data();
    if (current.hostUid !== uid || current.phase !== "night" || current.round !== room.round) {
      throw new HttpsError("aborted", "Night was already resolved or changed.");
    }
    for (const u of updates) tx.update(u.ref, u.data);
    for (const e of checks) {
      tx.set(roomRef.collection("private").doc(e.actorUid), {
        checkResult: roleByUid.get(e.targetUid) === "mafia", round: room.round, updatedAt: FieldValue.serverTimestamp()
      }, { merge: true });
    }
    tx.update(roomRef, {
      phase: winner ? "finished" : "talk",
      winner,
      updatedAt: FieldValue.serverTimestamp()
    });
  });
  return { ok: true, phase: winner ? "finished" : "talk", winner, killed: killTarget && killTarget !== saveTarget ? killTarget : null };
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
    if (room.hostUid !== uid) {
      throw new HttpsError("permission-denied", "Only the host can start voting.");
    }
    if (room.phase !== "talk") throw new HttpsError("failed-precondition", "Not a talk phase.");
    tx.update(roomRef, { phase: "vote", updatedAt: FieldValue.serverTimestamp() });
  });
  return { ok: true, phase: "vote" };
});

exports.resolveVote = onCall(async request => {
  const uid = authUid(request);
  const roomId = cleanRoomId(request.data?.roomId);
  await requireMember(roomId, uid);
  const roomRef = db.doc(`rooms/${roomId}`);
  const roomSnap = await roomRef.get();
  if (!roomSnap.exists) throw new HttpsError("not-found", "Room not found.");
  const room = roomSnap.data();
  if (room.hostUid !== uid) {
    throw new HttpsError("permission-denied", "Only the host can resolve the vote.");
  }
  if (room.phase !== "vote") {
    throw new HttpsError("failed-precondition", "Not a vote phase.");
  }
  const players = (await roomRef.collection("players").get()).docs;
  const privateDocs = await Promise.all(
    players.map(d => roomRef.collection("private").doc(d.id).get())
  );
  const roleByUid = new Map(
    privateDocs.filter(d => d.exists).map(d => [d.id, d.data().role])
  );

  const alive = new Set(players.filter(d => d.data().alive).map(d => d.id));
  const eventsSnap = await roomRef.collection("events").where("round", "==", room.round).get();
  const counts = new Map();
  for (const d of eventsSnap.docs) {
    const e = d.data();
    if (e.type === "vote" && alive.has(e.actorUid) && alive.has(e.targetUid) && e.actorUid !== e.targetUid) {
      counts.set(e.targetUid, (counts.get(e.targetUid) || 0) + 1);
    }
  }
  const maxVotes = Math.max(0, ...counts.values());
  const leaders = [...counts.entries()].filter(([, n]) => n === maxVotes && n > 0);
  const eliminated = leaders.length === 1 ? leaders[0][0] : null;

  const after = players.map(d => ({
    uid: d.id,
    ...d.data(),
    role: roleByUid.get(d.id),
    alive: d.id === eliminated ? false : d.data().alive
  }));
  const winner = winnerFor(after);
  await db.runTransaction(async tx => {
    const currentSnap = await tx.get(roomRef);
    if (!currentSnap.exists) throw new HttpsError("not-found", "Room not found.");
    const current = currentSnap.data();
    if (current.hostUid !== uid || current.phase !== "vote" || current.round !== room.round) {
      throw new HttpsError("aborted", "Vote was already resolved or changed.");
    }
    if (eliminated) {
      tx.update(roomRef.collection("players").doc(eliminated), { alive: false });
    }
    tx.update(roomRef, {
      phase: winner ? "finished" : "night",
      winner,
      round: winner ? room.round : room.round + 1,
      updatedAt: FieldValue.serverTimestamp()
    });
  });
  return { ok: true, phase: winner ? "finished" : "night", winner, eliminated };
});
