import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OnlineGameService {
  OnlineGameService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        functions = functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;

  Future<User> ensureAnonymousUser() async {
    final current = auth.currentUser;
    if (current != null) return current;
    final result = await auth.signInAnonymously();
    return result.user!;
  }

  Future<Map<String, dynamic>> createRoom({
    required String name,
    required int size,
  }) async {
    await ensureAnonymousUser();
    final result = await functions.httpsCallable('createRoom').call({
      'name': name,
      'size': size,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> joinRoom({
    required String roomId,
    required String name,
  }) async {
    await ensureAnonymousUser();
    final result = await functions.httpsCallable('joinRoom').call({
      'roomId': roomId,
      'name': name,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> leaveRoom(String roomId) async {
    await functions.httpsCallable('leaveRoom').call({'roomId': roomId});
  }

  Future<void> startGame(String roomId) async {
    await functions.httpsCallable('startGame').call({'roomId': roomId});
  }

  Future<String> getMyRole(String roomId) async {
    final result =
        await functions.httpsCallable('getMyRole').call({'roomId': roomId});
    return Map<String, dynamic>.from(result.data as Map)['role'] as String;
  }

  Future<void> submitAction({
    required String roomId,
    required String type,
    required String targetUid,
  }) async {
    await functions.httpsCallable('submitAction').call({
      'roomId': roomId,
      'type': type,
      'targetUid': targetUid,
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchRoom(String roomId) {
    return firestore.collection('rooms').doc(roomId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPlayers(String roomId) {
    return firestore
        .collection('rooms')
        .doc(roomId)
        .collection('players')
        .orderBy('seat')
        .snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchMyPrivateState(
      String roomId) {
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Anonymous authentication is required.');
    }
    return firestore
        .collection('rooms')
        .doc(roomId)
        .collection('private')
        .doc(uid)
        .snapshots();
  }
}
