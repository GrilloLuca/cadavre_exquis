import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/domain/models/auth_error.dart';

/// The signed-in user and the ways to sign in and out. Notifies listeners
/// whenever the user signs in or out. Failures from the auth provider are
/// thrown as [AuthException]s.
abstract class AuthRepository extends ChangeNotifier {
  /// False until the first sign-in state is known, at startup.
  bool get isReady;

  /// Whether a user is signed in.
  bool get isAuthenticated;

  /// Email of the signed-in user, or null.
  String? get currentEmail;

  /// Whether the signed-in user can sign in with an email and password, and
  /// so must enter it again to confirm sensitive actions.
  bool get usesPassword;

  Future<void> signInWithEmail({
    required String email,
    required String password,
  });

  Future<void> registerWithEmail({
    required String email,
    required String password,
  });

  /// Signs in with Google. Returns false if the user dismissed the Google
  /// account picker.
  Future<bool> signInWithGoogle();

  /// Confirms the signed-in user's identity, as a recent sign-in is required
  /// before deleting an account: with [password] for email/password users,
  /// otherwise by picking the Google account again. Returns false if the
  /// user dismissed the Google account picker.
  Future<bool> reauthenticate({String? password});

  /// Permanently deletes the signed-in user, who must have just
  /// [reauthenticate]d.
  Future<void> deleteAccount();

  /// Signs out, also of Google, so the account picker shows next time.
  Future<void> signOut();
}
