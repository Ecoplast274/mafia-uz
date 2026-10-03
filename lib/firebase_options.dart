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

  // Web build: keep the client configuration in source so GitHub Pages builds
  // do not depend on --dart-define values being supplied by the deployment.
  // Project: mafia-uz-82794
  static const web = FirebaseOptions(
    apiKey: 'AIzaSyBpZ5NUYKkRkZV2xx-gWY4ocN46rBJSyKI',
    appId: '1:692056725984:android:8f9f38f30cd5b0ca7db385',
    messagingSenderId: '692056725984',
    projectId: 'mafia-uz-82794',
    authDomain: 'mafia-uz-82794.firebaseapp.com',
    storageBucket: 'mafia-uz-82794.firebasestorage.app',
  );

  // Android Firebase client registered in project mafia-uz-82794.
  static const android = FirebaseOptions(
    apiKey: 'AIzaSyBpZ5NUYKkRkZV2xx-gWY4ocN46rBJSyKI',
    appId: '1:692056725984:android:8f9f38f30cd5b0ca7db385',
    messagingSenderId: '692056725984',
    projectId: 'mafia-uz-82794',
    storageBucket: 'mafia-uz-82794.firebasestorage.app',
  );
}
