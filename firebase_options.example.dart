import 'package:firebase_core/firebase_core.dart';

/// Copy this file to firebase_options.dart after registering the Android and
/// Web apps in Firebase. Never put a server/service-account key here.
///
/// The generated file is intentionally not committed to this repository until
/// the Firebase app registrations are completed.
class FirebaseConfigTemplate {
  static const projectId = 'mafia-uz-82794';
}

/// Production client initialization should use the FlutterFire-generated
/// DefaultFirebaseOptions from firebase_options.dart and:
///
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
///
/// Firebase API keys are public identifiers, but server credentials must
/// never be shipped in the Flutter app.
Future<void> validateFirebaseSdk() async {
  // Keeps firebase_core referenced in the template so the file is checked
  // by Dart tooling when copied into the project.
  FirebaseApp? app;
  app = null;
  if (app != null) {
    await app.delete();
  }
}
