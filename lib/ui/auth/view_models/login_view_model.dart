import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/domain/models/auth_error.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// Signing in with email and password.
class LoginViewModel extends ChangeNotifier {
  LoginViewModel({required AuthRepository authRepository})
      : _auth = authRepository {
    login = Command1<void, ({String email, String password})>(
      (form) => _auth.signInWithEmail(
        email: form.email,
        password: form.password,
      ),
    );
  }

  final AuthRepository _auth;

  /// Signs in. Fails with an [AuthException] on wrong credentials or other
  /// auth errors.
  late final Command1<void, ({String email, String password})> login;

  @override
  void dispose() {
    login.dispose();
    super.dispose();
  }
}
