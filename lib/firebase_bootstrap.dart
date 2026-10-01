import 'package:firebase_core/firebase_core.dart';

/// Initializes Firebase only when complete client configuration is supplied
/// through --dart-define values. No server credentials are embedded.
Future<bool> initializeFirebaseFromEnvironment() async {
  const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  const appId = String.fromEnvironment('FIREBASE_APP_ID');
  const messagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  const projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'mafia-uz-82794',
  );
  const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  const storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  if (apiKey.isEmpty ||
      appId.isEmpty ||
      messagingSenderId.isEmpty ||
      projectId.isEmpty) {
    return false;
  }

  try {
    if (Firebase.apps.isNotEmpty) return true;
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
    return true;
  } on FirebaseException {
    return false;
  }
}
