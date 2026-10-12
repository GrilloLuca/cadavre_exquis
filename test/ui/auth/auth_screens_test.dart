import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/domain/models/auth_error.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/screens/home_screen.dart';
import 'package:cadavre_exquisite/ui/auth/widgets/login_screen.dart';
import 'package:cadavre_exquisite/ui/auth/widgets/registration_screen.dart';
import 'package:cadavre_exquisite/ui/auth/widgets/welcome_screen.dart';

import '../../../testing/fakes/repositories/fake_auth_repository.dart';

void main() {
  late AppLocalizations l10n;
  late FakeAuthRepository auth;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() => auth = FakeAuthRepository());

  /// Pumps [home]; reaching the home route shows a "home" placeholder.
  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(ChangeNotifierProvider<AuthRepository>.value(
      value: auth,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: home,
        routes: {HomeScreen.id: (_) => const Text('home')},
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> fillAndTap(
      WidgetTester tester, String email, String password, String button) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), email);
    await tester.enterText(fields.at(1), password);
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
  }

  group('LoginScreen', () {
    Widget screen() => const LoginScreen();

    testWidgets('signs in and goes home', (tester) async {
      await pump(tester, screen());
      await fillAndTap(tester, 'a@x.it', 'secret', l10n.loginButton);

      expect(find.text('home'), findsOneWidget);
      expect(auth.currentEmail, 'a@x.it');
    });

    testWidgets('wrong credentials show their message', (tester) async {
      await pump(tester, screen());
      await fillAndTap(
          tester, 'a@x.it', FakeAuthRepository.wrongPassword, l10n.loginButton);

      expect(find.text(l10n.loginInvalidCredentials), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('other auth errors show the provider message', (tester) async {
      auth.failWith =
          const AuthException(AuthErrorCode.other, message: 'Too many tries');
      await pump(tester, screen());
      await fillAndTap(tester, 'a@x.it', 'secret', l10n.loginButton);

      expect(find.text('Too many tries'), findsOneWidget);
    });
  });

  group('RegistrationScreen', () {
    Widget screen() => const RegistrationScreen();

    testWidgets('registers and goes home', (tester) async {
      await pump(tester, screen());
      await fillAndTap(tester, 'a@x.it', 'secret1', l10n.registerButton);

      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a short password is caught by the form', (tester) async {
      await pump(tester, screen());
      await fillAndTap(tester, 'a@x.it', '123', l10n.registerButton);

      expect(find.text(l10n.passwordTooShort), findsOneWidget);
      expect(auth.isAuthenticated, isFalse);
    });

    testWidgets('a failure without message shows the generic one',
        (tester) async {
      auth.failWith = Exception('offline');
      await pump(tester, screen());
      await fillAndTap(tester, 'a@x.it', 'secret1', l10n.registerButton);

      expect(find.text(l10n.registrationFailed), findsOneWidget);
    });
  });

  group('WelcomeScreen', () {
    testWidgets('Google sign-in goes home', (tester) async {
      await pump(tester, const WelcomeScreen());
      await tester.tap(find.text(l10n.googleSignInButton));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('dismissing the picker stays on the screen', (tester) async {
      auth.googlePickerConfirms = false;
      await pump(tester, const WelcomeScreen());
      await tester.tap(find.text(l10n.googleSignInButton));
      await tester.pumpAndSettle();

      expect(find.text(l10n.googleSignInButton), findsOneWidget);
      expect(find.text(l10n.loginFailed), findsNothing);
    });

    testWidgets('a failure shows the login error', (tester) async {
      auth.failWith = Exception('network');
      await pump(tester, const WelcomeScreen());
      await tester.tap(find.text(l10n.googleSignInButton));
      await tester.pumpAndSettle();

      expect(find.text(l10n.loginFailed), findsOneWidget);
      expect(find.text(l10n.googleSignInButton), findsOneWidget);
    });
  });
}
