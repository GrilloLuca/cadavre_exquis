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

  /// Whether the signed-in user can sign in with an email and password, and
  /// so must enter it again to confirm sensitive actions.
  static bool get usesPassword =>
      FirebaseAuth.instance.currentUser?.providerData
          .any((info) => info.providerId == EmailAuthProvider.PROVIDER_ID) ??
      false;

  /// Confirms the signed-in user's identity, as Firebase requires a recent
  /// sign-in before deleting an account: with [password] for email/password
  /// users, otherwise by picking the Google account again. Returns false if
  /// the user dismissed the Google account picker.
  static Future<bool> reauthenticate({String? password}) async {
    final user = FirebaseAuth.instance.currentUser!;
    final AuthCredential credential;
    if (password != null) {
      credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
    } else {
      final GoogleSignInAccount account;
      try {
        account = await GoogleSignIn.instance.authenticate();
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled) return false;
        rethrow;
      }
      credential = GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      );
    }
    await user.reauthenticateWithCredential(credential);
    return true;
  }

  /// Permanently deletes the signed-in user, who must have just
  /// [reauthenticate]d. The `anonymizeDeletedUser` Cloud Function then
  /// removes their email from Firestore.
  static Future<void> deleteAccount() async {
    await FirebaseAuth.instance.currentUser!.delete();
    await GoogleSignIn.instance.signOut();
  }

  /// Signs out of Firebase and Google, so the account picker shows next time.
  static Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await FirebaseAuth.instance.signOut();
  }
}
