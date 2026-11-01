import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/feature_flags/feature_flags_repository.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// Signing in with Google from the welcome screen, and whether the
/// email/password login is offered too.
class WelcomeViewModel extends ChangeNotifier {
  WelcomeViewModel({
    required AuthRepository authRepository,
    required FeatureFlagsRepository featureFlags,
    bool? isIos,
    bool debugBuild = kDebugMode,
  })  : _auth = authRepository,
        _debugBuild = debugBuild {
    signInWithGoogle = Command0<bool>(_auth.signInWithGoogle);
    final ios =
        isIos ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);
    if (ios) {
      _flagSubscription = featureFlags.watchEmailLoginOnIos().listen((on) {
        if (on == _emailLoginOnIos) return;
        _emailLoginOnIos = on;
        notifyListeners();
      });
    }
  }

  final AuthRepository _auth;
  final bool _debugBuild;
  StreamSubscription<bool>? _flagSubscription;
  bool _emailLoginOnIos = false;

  /// Signs in with Google; its value is false if the user dismissed the
  /// account picker.
  late final Command0<bool> signInWithGoogle;

  /// Whether to show the email/password login button: always in debug
  /// builds, and on iOS while the `appConfig/flags.iosEmailLogin` flag is
  /// on (the App Store review signs in with a demo account).
  bool get showEmailLogin => _debugBuild || _emailLoginOnIos;

  @override
  void dispose() {
    _flagSubscription?.cancel();
    signInWithGoogle.dispose();
    super.dispose();
  }
}
