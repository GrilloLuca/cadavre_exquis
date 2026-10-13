import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/room/room_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/account/widgets/account_screen.dart';
import 'package:cadavre_exquisite/ui/auth/widgets/welcome_screen.dart';

import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_room_repository.dart';
import '../../../testing/fakes/repositories/fake_user_profile_repository.dart';

void main() {
  late AppLocalizations l10n;
  late FakeAuthRepository auth;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() => auth = FakeAuthRepository(email: 'me@example.com'));

  /// Reaching the welcome route shows a "welcome" placeholder.
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<UserProfileRepository>(
            create: (_) => FakeUserProfileRepository()),
        ChangeNotifierProvider<AuthRepository>.value(value: auth),
        ChangeNotifierProvider<RoomRepository>(
            create: (_) => FakeRoomRepository()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const AccountScreen(),
        // A Scaffold, like the real welcome screen, so the snack bar shows.
        routes: {
          WelcomeScreen.id: (_) => const Scaffold(body: Text('welcome')),
        },
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> deleteWith(WidgetTester tester, String password) async {
    await tester.tap(find.text(l10n.deleteAccountButton));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        password);
    await tester.tap(find.text(l10n.deleteAccountConfirmButton));
    await tester.pumpAndSettle();
  }

  testWidgets('a wrong password keeps the account and says so', (tester) async {
    await pump(tester);
    await deleteWith(tester, FakeAuthRepository.wrongPassword);

    expect(find.text(l10n.loginInvalidCredentials), findsOneWidget);
    expect(find.byType(AccountScreen), findsOneWidget);
    expect(auth.isAuthenticated, isTrue);
  });

  testWidgets('deleting the account goes back to the welcome screen',
      (tester) async {
    await pump(tester);
    await deleteWith(tester, 'secret');

    expect(find.text('welcome'), findsOneWidget);
    expect(find.text(l10n.accountDeleted), findsOneWidget);
    expect(auth.isAuthenticated, isFalse);
  });

  testWidgets('signing out goes back to the welcome screen', (tester) async {
    await pump(tester);
    await tester.tap(find.text(l10n.logoutButton));
    await tester.pumpAndSettle();

    expect(find.text('welcome'), findsOneWidget);
    expect(auth.isAuthenticated, isFalse);
  });
}
