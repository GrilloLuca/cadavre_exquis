import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/domain/models/auth_error.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// Creating an account with email and password.
class RegistrationViewModel extends ChangeNotifier {
  RegistrationViewModel({required AuthRepository authRepository})
      : _auth = authRepository {
    register = Command1<void, ({String email, String password})>(
      (form) => _auth.registerWithEmail(
        email: form.email,
        password: form.password,
      ),
    );
  }

  final AuthRepository _auth;

  /// Registers and signs in. Fails with an [AuthException], e.g.
  /// [AuthErrorCode.weakPassword].
  late final Command1<void, ({String email, String password})> register;

  @override
  void dispose() {
    register.dispose();
    super.dispose();
  }
}
