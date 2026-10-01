import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class OnlinePlayer {
  final String uid;
  final String name;
  final int seat;
  final bool alive;

  const OnlinePlayer({
    required this.uid,
    required this.name,
    required this.seat,
    required this.alive,
  });

  factory OnlinePlayer.fromMap(String uid, Map<String, dynamic> data) {
    return OnlinePlayer(
      uid: uid,
      name: (data['name'] ?? '').toString(),
      seat: (data['seat'] as num?)?.toInt() ?? 0,
      alive: data['alive'] != false,
    );
  }
}

class OnlineRoom {
  final String roomId;
  final int size;
  final String phase;
  final int round;
  final String? hostUid;
  final String? winner;
  final List<OnlinePlayer> players;

  const OnlineRoom({
    required this.roomId,
    required this.size,
    required this.phase,
    required this.round,
    required this.hostUid,
    required this.winner,
    required this.players,
  });

  factory OnlineRoom.fromSnapshots(
    DocumentSnapshot<Map<String, dynamic>> room,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> players,
  ) {
    final data = room.data() ?? <String, dynamic>{};
    final ordered = [...players]..sort((a, b) {
        final sa = (a.data()['seat'] as num?)?.toInt() ?? 0;
        final sb = (b.data()['seat'] as num?)?.toInt() ?? 0;
        return sa.compareTo(sb);
      });
    return OnlineRoom(
      roomId: (data['roomId'] ?? room.id).toString(),
      size: (data['size'] as num?)?.toInt() ?? 8,
      phase: (data['phase'] ?? 'lobby').toString(),
      round: (data['round'] as num?)?.toInt() ?? 0,
      hostUid: data['hostUid'] as String?,
      winner: data['winner'] as String?,
      players: [
        for (final doc in ordered) OnlinePlayer.fromMap(doc.id, doc.data()),
      ],
    );
  }
}

class MultiplayerService {
  MultiplayerService._();
  static final instance = MultiplayerService._();

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  bool get configured => Firebase.apps.isNotEmpty;
  String? get currentUid => _auth.currentUser?.uid;

  Future<User> ensureAnonymousAuth() async {
    if (!configured) {
      throw StateError('Firebase client konfiguratsiyasi hali kiritilmagan.');
    }
    final current = _auth.currentUser;
    if (current != null) return current;
    final credential = await _auth.signInAnonymously();
    return credential.user!;
  }

  Future<String> createRoom({required int size, required String name}) async {
    await ensureAnonymousAuth();
    final result = await _functions.httpsCallable('createRoom').call({
      'size': size,
      'name': name,
    });
    return result.data['roomId'].toString();
  }

  Future<void> joinRoom({required String roomId, required String name}) async {
    await ensureAnonymousAuth();
    await _functions.httpsCallable('joinRoom').call({
      'roomId': roomId.trim().toUpperCase(),
      'name': name.trim(),
    });
  }

  Future<void> leaveRoom(String roomId) async {
    await ensureAnonymousAuth();
    await _functions.httpsCallable('leaveRoom').call({'roomId': roomId});
  }

  Future<void> startGame(String roomId) async {
    await ensureAnonymousAuth();
    await _functions.httpsCallable('startGame').call({'roomId': roomId});
  }

  Future<void> submitAction({
    required String roomId,
    required String type,
    required String targetUid,
  }) async {
    await ensureAnonymousAuth();
    await _functions.httpsCallable('submitAction').call({
      'roomId': roomId,
      'type': type,
      'targetUid': targetUid,
    });
  }

  Future<void> resolveNight(String roomId) async {
    await ensureAnonymousAuth();
    await _functions.httpsCallable('resolveNight').call({'roomId': roomId});
  }

  Future<void> startVote(String roomId) async {
    await ensureAnonymousAuth();
    await _functions.httpsCallable('startVote').call({'roomId': roomId});
  }

  Future<void> resolveVote(String roomId) async {
    await ensureAnonymousAuth();
    await _functions.httpsCallable('resolveVote').call({'roomId': roomId});
  }

  Stream<OnlineRoom> watchRoom(String roomId) {
    final roomStream = _db.doc('rooms/$roomId').snapshots();
    return roomStream.asyncMap((roomSnap) async {
      final playersSnap =
          await _db.collection('rooms/$roomId/players').get();
      return OnlineRoom.fromSnapshots(roomSnap, playersSnap.docs);
    });
  }
}
