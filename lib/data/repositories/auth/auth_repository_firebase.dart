import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/services/google_sign_in_service.dart';
import 'package:cadavre_exquisite/domain/models/auth_error.dart';

/// [AuthRepository] backed by Firebase Auth, with Google accounts linked
/// through [GoogleSignInService].
class AuthRepositoryFirebase extends AuthRepository {
  AuthRepositoryFirebase({
    required GoogleSignInService googleSignIn,
    FirebaseAuth? auth,
  })  : _googleSignIn = googleSignIn,
        _auth = auth ?? FirebaseAuth.instance {
    _subscription = _auth.authStateChanges().listen((user) {
      _isReady = true;
      _isAuthenticated = user != null;
      notifyListeners();
    });
  }

  final GoogleSignInService _googleSignIn;
  final FirebaseAuth _auth;
  late final StreamSubscription<User?> _subscription;

  bool _isReady = false;
  bool _isAuthenticated = false;

  @override
  bool get isReady => _isReady;

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  String? get currentEmail => _auth.currentUser?.email;

  @override
  bool get usesPassword =>
      _auth.currentUser?.providerData
          .any((info) => info.providerId == EmailAuthProvider.PROVIDER_ID) ??
      false;

  /// Runs [action], turning Firebase Auth failures into [AuthException]s.
  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      throw AuthException(_codeOf(e), message: e.message);
    }
  }

  static AuthErrorCode _codeOf(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return AuthErrorCode.invalidCredentials;
      case 'weak-password':
        return AuthErrorCode.weakPassword;
      default:
        return AuthErrorCode.other;
    }
  }

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) =>
      _guard(() => _auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          ));

  @override
  Future<void> registerWithEmail({
    required String email,
    required String password,
  }) =>
      _guard(() => _auth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          ));

  @override
  Future<bool> signInWithGoogle() => _guard(() async {
        final idToken = await _googleSignIn.authenticate();
        if (idToken == null) return false;
        await _auth.signInWithCredential(
          GoogleAuthProvider.credential(idToken: idToken),
        );
        return true;
      });

  @override
  Future<bool> reauthenticate({String? password}) => _guard(() async {
        final user = _auth.currentUser!;
        final AuthCredential credential;
        if (password != null) {
          credential = EmailAuthProvider.credential(
            email: user.email!,
            password: password,
          );
        } else {
          final idToken = await _googleSignIn.authenticate();
          if (idToken == null) return false;
          credential = GoogleAuthProvider.credential(idToken: idToken);
        }
        await user.reauthenticateWithCredential(credential);
        return true;
      });

  /// The `anonymizeDeletedUser` Cloud Function then removes the user's
  /// email from Firestore.
  @override
  Future<void> deleteAccount() => _guard(() async {
        await _auth.currentUser!.delete();
        await _googleSignIn.signOut();
      });

  @override
  Future<void> signOut() => _guard(() async {
        await _googleSignIn.signOut();
        await _auth.signOut();
      });

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
