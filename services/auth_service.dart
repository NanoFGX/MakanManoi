import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  static final _auth = FirebaseAuth.instance;

  static Future<void> ensureAnon() async {
    if (_auth.currentUser != null) return;
    await _auth.signInAnonymously();
  }

  static String get uid => _auth.currentUser?.uid ?? "unknown";
}