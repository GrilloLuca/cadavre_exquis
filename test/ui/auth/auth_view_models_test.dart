import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/domain/models/auth_error.dart';
import 'package:cadavre_exquisite/ui/auth/view_models/login_view_model.dart';
import 'package:cadavre_exquisite/ui/auth/view_models/registration_view_model.dart';
import 'package:cadavre_exquisite/ui/auth/view_models/welcome_view_model.dart';

import '../../../testing/fakes/repositories/fake_auth_repository.dart';

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
    final viewModel = WelcomeViewModel(authRepository: auth);

    auth.googlePickerConfirms = false;
    await viewModel.signInWithGoogle.execute();
    expect(viewModel.signInWithGoogle.value, isFalse);
    expect(auth.isAuthenticated, isFalse);

    auth.googlePickerConfirms = true;
    await viewModel.signInWithGoogle.execute();
    expect(viewModel.signInWithGoogle.value, isTrue);
    expect(auth.isAuthenticated, isTrue);
  });
}
