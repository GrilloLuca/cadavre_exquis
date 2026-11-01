import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/domain/models/auth_error.dart';
import 'package:cadavre_exquisite/ui/auth/view_models/login_view_model.dart';
import 'package:cadavre_exquisite/ui/auth/view_models/registration_view_model.dart';
import 'package:cadavre_exquisite/ui/auth/view_models/welcome_view_model.dart';

import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_feature_flags_repository.dart';

Matcher _authError(AuthErrorCode code) =>
    isA<AuthException>().having((e) => e.code, 'code', code);

void main() {
  late FakeAuthRepository auth;

  setUp(() => auth = FakeAuthRepository());

  test('login signs in, wrong credentials fail', () async {
    final viewModel = LoginViewModel(authRepository: auth);

    await viewModel.login.execute((email: 'a@x.it', password: 'wrong'));
    expect(viewModel.login.error, _authError(AuthErrorCode.invalidCredentials));
    expect(auth.isAuthenticated, isFalse);

    await viewModel.login.execute((email: 'a@x.it', password: 'secret'));
    expect(viewModel.login.completed, isTrue);
    expect(auth.currentEmail, 'a@x.it');
  });

  test('registration reports a weak password', () async {
    final viewModel = RegistrationViewModel(authRepository: auth);

    await viewModel.register.execute((email: 'a@x.it', password: '123'));
    expect(viewModel.register.error, _authError(AuthErrorCode.weakPassword));

    await viewModel.register.execute((email: 'a@x.it', password: '123456'));
    expect(viewModel.register.completed, isTrue);
    expect(auth.currentEmail, 'a@x.it');
  });

  test('Google sign-in: true when signed in, false when dismissed', () async {
    final viewModel = WelcomeViewModel(
        authRepository: auth, featureFlags: FakeFeatureFlagsRepository());

    auth.googlePickerConfirms = false;
    await viewModel.signInWithGoogle.execute();
    expect(viewModel.signInWithGoogle.value, isFalse);
    expect(auth.isAuthenticated, isFalse);

    auth.googlePickerConfirms = true;
    await viewModel.signInWithGoogle.execute();
    expect(viewModel.signInWithGoogle.value, isTrue);
    expect(auth.isAuthenticated, isTrue);
  });

  group('email login button', () {
    WelcomeViewModel build(FakeFeatureFlagsRepository flags,
            {required bool isIos, bool debugBuild = false}) =>
        WelcomeViewModel(
          authRepository: auth,
          featureFlags: flags,
          isIos: isIos,
          debugBuild: debugBuild,
        );

    test('on iOS it follows the flag', () async {
      final flags = FakeFeatureFlagsRepository();
      final viewModel = build(flags, isIos: true);
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.showEmailLogin, isFalse);

      flags.setEmailLoginOnIos(true);
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.showEmailLogin, isTrue);

      flags.setEmailLoginOnIos(false);
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.showEmailLogin, isFalse);
      viewModel.dispose();
    });

    test('elsewhere the flag is ignored', () async {
      final flags = FakeFeatureFlagsRepository(emailLoginOnIos: true);
      final viewModel = build(flags, isIos: false);
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.showEmailLogin, isFalse);
      viewModel.dispose();
    });

    test('debug builds always show it', () async {
      final viewModel =
          build(FakeFeatureFlagsRepository(), isIos: false, debugBuild: true);
      expect(viewModel.showEmailLogin, isTrue);
      viewModel.dispose();
    });
  });
}
