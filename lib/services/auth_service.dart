import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService._();

  /// Must be awaited once at startup, before any other Google Sign-In call.
  static Future<void> initialize() => GoogleSignIn.instance.initialize();

  /// Signs in with Google and links the account to Firebase.
  /// Returns null if the user dismissed the Google account picker.
  static Future<UserCredential?> signInWithGoogle() async {
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }

    final credential = GoogleAuthProvider.credential(
      idToken: account.authentication.idToken,
    );
    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  /// Signs out of Firebase and Google, so the account picker shows next time.
  static Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await FirebaseAuth.instance.signOut();
  }
}
