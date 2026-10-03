import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

class MafiaOnlineService {
  MafiaOnlineService._();
  static final instance = MafiaOnlineService._();

  bool initialized = false;
  String? initError;

  FirebaseFunctions get functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  Future<bool> initialize() async {
    if (initialized) return true;
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const messagingSenderId =
        String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const projectId =
        String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'mafia-uz-82794');
    const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
    const storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
    const appCheckEnabled = String.fromEnvironment('FIREBASE_APPCHECK_ENABLED', defaultValue: 'false') == 'true';
    const appCheckWebSiteKey = String.fromEnvironment('FIREBASE_APPCHECK_WEB_SITE_KEY');

    if (apiKey.isEmpty || appId.isEmpty || messagingSenderId.isEmpty) {
      initError = 'Firebase client configuration is not supplied.';
      return false;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: apiKey,
            appId: appId,
            messagingSenderId: messagingSenderId,
            projectId: projectId,
            authDomain: authDomain.isEmpty ? null : authDomain,
            storageBucket: storageBucket.isEmpty ? null : storageBucket,
          ),
        );
      }
      if (appCheckEnabled) {
        if (kIsWeb) {
          if (appCheckWebSiteKey.isEmpty) {
            throw StateError('Firebase App Check web site key is missing.');
          }
          await FirebaseAppCheck.instance.activate(
            webProvider: ReCaptchaV3Provider(appCheckWebSiteKey),
          );
        } else {
          await FirebaseAppCheck.instance.activate(
            androidProvider: AndroidProvider.playIntegrity,
          );
        }
      }
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      initialized = true;
      initError = null;
      return true;
    } on FirebaseException catch (e) {
      initError = e.code + ': ' + (e.message ?? 'Firebase initialization failed.');
      return false;
    } catch (e) {
      initError = e.toString();
      return false;
    }
  }

  User? get user => initialized ? FirebaseAuth.instance.currentUser : null;

  Future<String> createRoom({required int size, required String name}) async {
    _requireReady();
    final result = await functions.httpsCallable('createRoom').call({
      'size': size,
      'name': name,
    });
    return (result.data as Map)['roomId'] as String;
  }

  Future<void> joinRoom({required String roomId, required String name}) async {
    _requireReady();
    await functions.httpsCallable('joinRoom').call({
      'roomId': roomId,
      'name': name,
    });
  }

  Future<void> leaveRoom(String roomId) async {
    _requireReady();
    await functions.httpsCallable('leaveRoom').call({'roomId': roomId});
  }

  Future<void> startGame(String roomId) async {
    _requireReady();
    await functions.httpsCallable('startGame').call({'roomId': roomId});
  }

  Future<Map<String, dynamic>> getMyRole(String roomId) async {
    _requireReady();
    final result =
        await functions.httpsCallable('getMyRole').call({'roomId': roomId});
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> submitAction({
    required String roomId,
    required String type,
    required String targetUid,
  }) async {
    _requireReady();
    await functions.httpsCallable('submitAction').call({
      'roomId': roomId,
      'type': type,
      'targetUid': targetUid,
    });
  }

  Future<void> resolveNight(String roomId) async {
    _requireReady();
    await functions.httpsCallable('resolveNight').call({'roomId': roomId});
  }

  Future<void> startVote(String roomId) async {
    _requireReady();
    await functions.httpsCallable('startVote').call({'roomId': roomId});
  }

  Future<void> resolveVote(String roomId) async {
    _requireReady();
    await functions.httpsCallable('resolveVote').call({'roomId': roomId});
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> roomStream(String roomId) {
    _requireReady();
    return FirebaseFirestore.instance.doc('rooms/' + roomId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> playersStream(String roomId) {
    _requireReady();
    return FirebaseFirestore.instance
        .collection('rooms/' + roomId + '/players')
        .orderBy('seat')
        .snapshots();
  }

  void _requireReady() {
    if (!initialized) {
      throw StateError(
        initError ?? 'Firebase is not initialized. Supply client configuration.',
      );
    }
  }

  bool get supported =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;
}
