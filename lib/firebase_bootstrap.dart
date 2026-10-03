import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<bool> initializeFirebaseFromEnvironment() async {
  try {
    if (Firebase.apps.isNotEmpty) return true;
    final options = DefaultFirebaseOptions.currentPlatform;
    if (options.apiKey.isEmpty || options.appId.isEmpty || options.projectId.isEmpty) {
      return false;
    }
    await Firebase.initializeApp(options: options);
    return true;
  } on FirebaseException {
    return false;
  } catch (_) {
    return false;
  }
}
