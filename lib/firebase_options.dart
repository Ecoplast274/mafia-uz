import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('Firebase is configured only for Android and Web.');
    }
  }

  static const web = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
    appId: String.fromEnvironment('FIREBASE_APP_ID'),
    messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'mafia-uz-82794'),
    authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
    storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
  );

  // Android Firebase client registered in project mafia-uz-82794.
  // Values are from the Firebase-generated google-services.json.
  static const android = FirebaseOptions(
    apiKey: 'AIzaSyBpZ5NUYKkRkZV2xx-gWY4ocN46rBJSyKI',
    appId: '1:692056725984:android:8f9f38f30cd5b0ca7db385',
    messagingSenderId: '692056725984',
    projectId: 'mafia-uz-82794',
    storageBucket: 'mafia-uz-82794.firebasestorage.app',
  );
}
