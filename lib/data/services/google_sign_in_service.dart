import 'package:google_sign_in/google_sign_in.dart';

/// Thin wrapper over the Google Sign-In SDK, so [AuthRepositoryFirebase]
/// can be tested without the platform plugin.
class GoogleSignInService {
  GoogleSignInService({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final GoogleSignIn _googleSignIn;

  /// Must be awaited once at startup, before any other Google Sign-In call.
  Future<void> initialize() => _googleSignIn.initialize();

  /// Shows the Google account picker and returns the ID token of the chosen
  /// account, or null if the user dismissed the picker.
  Future<String?> authenticate() async {
    try {
      final account = await _googleSignIn.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  /// Signs out of Google, so the account picker shows next time.
  Future<void> signOut() => _googleSignIn.signOut();
}
