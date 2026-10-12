import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// Signing in with Google from the welcome screen.
class WelcomeViewModel extends ChangeNotifier {
  WelcomeViewModel({required AuthRepository authRepository})
      : _auth = authRepository {
    signInWithGoogle = Command0<bool>(_auth.signInWithGoogle);
  }

  final AuthRepository _auth;

  /// Signs in with Google; its value is false if the user dismissed the
  /// account picker.
  late final Command0<bool> signInWithGoogle;

  @override
  void dispose() {
    signInWithGoogle.dispose();
    super.dispose();
  }
}
