import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase client configuration.
///
/// The Web Firebase config is a public client configuration issued for the
/// registered Mafia UZ Web app. Server credentials must never be shipped here.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'Firebase is configured only for Android and Web.',
        );
    }
  }

  static const web = FirebaseOptions(
    apiKey: 'AIzaSyATgpDOAp9o6ZamGpuGvrh6AkjVwJ4dbHc',
    appId: '1:692056725984:web:add73fbd7dbfb2487db385',
    messagingSenderId: '692056725984',
    projectId: 'mafia-uz-82794',
    authDomain: 'mafia-uz-82794.firebaseapp.com',
    storageBucket: 'mafia-uz-82794.firebasestorage.app',
  );

  static const android = FirebaseOptions(
    apiKey: String.fromEnvironment(
      'FIREBASE_API_KEY',
      defaultValue: 'AIzaSyBpZ5NUYKkRkV2xx-gWY4ocN46rBJSyKI',
    ),
    appId: String.fromEnvironment(
      'FIREBASE_ANDROID_APP_ID',
      defaultValue: '1:692056725984:android:8f9f38f30cd5b0ca7db385',
    ),
    messagingSenderId: String.fromEnvironment(
      'FIREBASE_MESSAGING_SENDER_ID',
      defaultValue: '692056725984',
    ),
    projectId: String.fromEnvironment(
      'FIREBASE_PROJECT_ID',
      defaultValue: 'mafia-uz-82794',
    ),
    authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
    storageBucket: String.fromEnvironment(
      'FIREBASE_STORAGE_BUCKET',
      defaultValue: 'mafia-uz-82794.firebasestorage.app',
    ),
  );
}
