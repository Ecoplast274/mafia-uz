const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { initializeApp } = require("firebase-admin/app");

initializeApp();
setGlobalOptions({
  region: "asia-southeast1",
  maxInstances: 20,
  concurrency: 80,
});

const db = getFirestore();
const ROOM_SIZES = new Set([8, 12]);
const PHASES = new Set(["lobby", "night", "talk", "vote", "finished"]);
const ROLES = ["mafia", "doctor", "sheriff", "citizen"];

function authUid(request) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
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
  const roles = [
    ...Array(mafiaCount(size)).fill("mafia"),
    "doctor",
    "sheriff",
  ];
  while (roles.length < size) roles.push("citizen");
  for (let i = roles.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [roles[i], roles[j]] = [roles[j], roles[i]];
  }
  return roles;
}

function randomRoomId() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let out = "";
  for (let i = 0; i < 6; i++) {
    out += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return out;
}

async function requireMember(roomId, uid) {
  const snap = await db.doc(`rooms/${roomId}/players/${uid}`).get();
  if (!snap.exists) {
    throw new HttpsError("permission-denied", "You are not a member of this room.");
  }
  return snap.data();
}

exports.createRoom = onCall(async (request) => {
  const uid = authUid(request);
  const size = Number(request.data?.size);
  const name = cleanName(request.data?.name);
  if (!ROOM_SIZES.has(size)) {
    throw new HttpsError("invalid-argument", "Room size must be 8 or 12.");
  }

  for (let attempt = 0; attempt < 5; attempt++) {
    const roomId = randomRoomId();
    const roomRef = db.doc(`rooms/${roomId}`);
    const playerRef = roomRef.collection("players").doc(uid);
    try {
      await db.runTransaction(async (tx) => {
        const existing = await tx.get(roomRef);
        if (existing.exists) throw new Error("collision");
        tx.create(roomRef, {
          roomId,
          size,
          hostUid: uid,
          phase: "lobby",
          round: 0,
          winner: null,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        tx.create(playerRef, {
          uid,
          name,
          seat: 0,
          alive: true,
          joinedAt: FieldValue.serverTimestamp(),
        });
      });
      return { roomId, size, host: true };
    } catch (e) {
      if (e.message !== "collision") throw e;
    }
  }
  throw new HttpsError("aborted", "Could not allocate a room.");
});

exports.joinRoom = onCall(async (request) => {
  const uid = authUid(request);
  const roomId = cleanRoomId(request.data?.roomId);
  const name = cleanName(request.data?.name);
  const roomRef = db.doc(`rooms/${roomId}`);
  const playerRef = roomRef.collection("players").doc(uid);

  await db.runTransaction(async (tx) => {
    const room = await tx.get(roomRef);
    if (!room.exists) throw new HttpsError("not-found", "Room not found.");
    const data = room.data();
    if (data.phase !== "lobby") {
      throw new HttpsError("failed-precondition", "Game has already started.");
    }

    const players = await tx.get(roomRef.collection("players"));
    const already = players.docs.some((d) => d.id === uid);
    if (already) {
      tx.update(playerRef, { name, updatedAt: FieldValue.serverTimestamp() });
      return;
    }
    if (players.size >= data.size) {
      throw new HttpsError("resource-exhausted", "Room is full.");
    }
    tx.create(playerRef, {
      uid,
      name,
      seat: players.size,
      alive: true,
      joinedAt: FieldValue.serverTimestamp(),
    });
    tx.update(roomRef, { updatedAt: FieldValue.serverTimestamp() });
  });

  const room = (await roomRef.get()).data();
  return { roomId, size: room.size, host: room.hostUid === uid };
});

exports.leaveRoom = onCall(async (request) => {
  const uid = authUid(request);
  const roomId = cleanRoomId(request.data?.roomId);
  const roomRef = db.doc(`rooms/${roomId}`);
  const playerRef = roomRef.collection("players").doc(uid);

  await db.runTransaction(async (tx) => {
    const room = await tx.get(roomRef);
    const player = await tx.get(playerRef);
    if (!room.exists || !player.exists) return;
    const data = room.data();
    if (data.phase !== "lobby") {
      throw new HttpsError("failed-precondition", "Cannot leave after game start.");
    }
    tx.delete(playerRef);
    tx.update(roomRef, { updatedAt: FieldValue.serverTimestamp() });
  });
  return { ok: true };
});

exports.startGame = onCall(async (request) => {
  const uid = authUid(request);
  const roomId = cleanRoomId(request.data?.roomId);
  const roomRef = db.doc(`rooms/${roomId}`);

  await db.runTransaction(async (tx) => {
    const roomSnap = await tx.get(roomRef);
    if (!roomSnap.exists) throw new HttpsError("not-found", "Room not found.");
    const room = roomSnap.data();
    if (room.hostUid !== uid) throw new HttpsError("permission-denied", "Only the host can start.");
    if (room.phase !== "lobby") throw new HttpsError("failed-precondition", "Game already started.");

    const playersSnap = await tx.get(roomRef.collection("players"));
    if (playersSnap.size !== room.size) {
      throw new HttpsError("failed-precondition", "Room must be full before starting.");
    }

    const roles = shuffledRoles(room.size);
    playersSnap.docs
      .sort((a, b) => Number(a.data().seat) - Number(b.data().seat))
      .forEach((doc, index) => {
        const role = roles[index];
        tx.set(roomRef.collection("private").doc(doc.id), {
          uid: doc.id,
          role,
          round: 1,
          updatedAt: FieldValue.serverTimestamp(),
        });
        tx.update(doc.ref, {
          alive: true,
          rolePublic: role === "citizen" ? "citizen" : "special",
        });
      });

    tx.update(roomRef, {
      phase: "night",
      round: 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return { ok: true, phase: "night" };
});

exports.getMyRole = onCall(async (request) => {
  const uid = authUid(request);
  const roomId = cleanRoomId(request.data?.roomId);
  await requireMember(roomId, uid);
  const snap = await db.doc(`rooms/${roomId}/private/${uid}`).get();
  if (!snap.exists) throw new HttpsError("failed-precondition", "Game has not started.");
  return { role: snap.data().role, round: snap.data().round };
});

exports.submitAction = onCall(async (request) => {
  const uid = authUid(request);
  const roomId = cleanRoomId(request.data?.roomId);
  const type = String(request.data?.type ?? "");
  const targetUid = String(request.data?.targetUid ?? "");
  if (!["kill", "save", "check", "vote"].includes(type) || !targetUid) {
    throw new HttpsError("invalid-argument", "Invalid action.");
  }

  const roomRef = db.doc(`rooms/${roomId}`);
  await requireMember(roomId, uid);

  await db.runTransaction(async (tx) => {
    const roomSnap = await tx.get(roomRef);
    const room = roomSnap.data();
    const actor = await tx.get(roomRef.collection("private").doc(uid));
    const target = await tx.get(roomRef.collection("players").doc(targetUid));
    if (!roomSnap.exists || !actor.exists || !target.exists) {
      throw new HttpsError("not-found", "Game data not found.");
    }
    if (!target.data().alive) throw new HttpsError("failed-precondition", "Target is dead.");

    const role = actor.data().role;
    const allowed = {
      kill: room.phase === "night" && role === "mafia",
      save: room.phase === "night" && role === "doctor",
      check: room.phase === "night" && role === "sheriff",
      vote: room.phase === "vote",
    };
    if (!allowed[type]) throw new HttpsError("failed-precondition", "Action is not allowed now.");
    if (targetUid === uid && type !== "save") {
      throw new HttpsError("invalid-argument", "Self-targeting is not allowed.");
    }

    const actionRef = roomRef.collection("events").doc();
    tx.create(actionRef, {
      type,
      actorUid: uid,
      targetUid,
      round: room.round,
      createdAt: FieldValue.serverTimestamp(),
    });
  });

  return { ok: true };
});
