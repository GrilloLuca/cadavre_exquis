import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/domain/models/auth_error.dart';

/// In-memory [AuthRepository] for ViewModel and widget tests. Starts ready,
/// signed in as [email] (or signed out when null). Accepts any password
/// except [wrongPassword].
class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository({String? email, this.usesPassword = true})
      : _email = email;

  String? _email;

  static const String wrongPassword = 'wrong';

  /// When false, [signInWithGoogle] and [reauthenticate] without a password
  /// behave as if the user dismissed the Google account picker.
  bool googlePickerConfirms = true;

  @override
  bool usesPassword;

  @override
  bool get isReady => true;

  @override
  bool get isAuthenticated => _email != null;

  @override
  String? get currentEmail => _email;

  void _signIn(String email) {
    _email = email;
    notifyListeners();
  }

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (password == wrongPassword) {
      throw const AuthException(AuthErrorCode.invalidCredentials);
    }
    _signIn(email);
  }

  @override
  Future<void> registerWithEmail({
    required String email,
    required String password,
  }) async {
    if (password.length < 6) {
      throw const AuthException(AuthErrorCode.weakPassword);
    }
    _signIn(email);
  }

  @override
  Future<bool> signInWithGoogle() async {
    if (!googlePickerConfirms) return false;
    _signIn('google.user@example.com');
    return true;
  }

  @override
  Future<bool> reauthenticate({String? password}) async {
    if (password == null) return googlePickerConfirms;
    if (password == wrongPassword) {
      throw const AuthException(AuthErrorCode.invalidCredentials);
    }
    return true;
  }

  @override
  Future<void> deleteAccount() async => signOut();

  @override
  Future<void> signOut() async {
    _email = null;
    notifyListeners();
  }
}
