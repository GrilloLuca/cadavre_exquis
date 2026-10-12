import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cadavre_exquisite/data/repositories/age_check/age_check_repository.dart';
import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/private_room/private_room_repository.dart';
import 'package:cadavre_exquisite/data/repositories/room/room_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/main.dart';
import 'package:cadavre_exquisite/ui/home/widgets/home_screen.dart';
import 'package:cadavre_exquisite/ui/auth/widgets/welcome_screen.dart';

import '../testing/fakes/repositories/fake_age_check_repository.dart';
import '../testing/fakes/repositories/fake_auth_repository.dart';
import '../testing/fakes/repositories/fake_private_room_repository.dart';
import '../testing/fakes/repositories/fake_room_repository.dart';
import '../testing/fakes/repositories/fake_story_repository.dart';
import '../testing/fakes/repositories/fake_user_profile_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'languageRoom': 'it'}));

  Widget buildApp(FakeAuthRepository auth) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthRepository>.value(value: auth),
          ChangeNotifierProvider<RoomRepository>(
              create: (_) => FakeRoomRepository()),
          Provider<StoryRepository>(create: (_) => FakeStoryRepository()),
          Provider<UserProfileRepository>(
              create: (_) => FakeUserProfileRepository()),
          Provider<AgeCheckRepository>(create: (_) => FakeAgeCheckRepository()),
          Provider<PrivateRoomRepository>(
              create: (_) => FakePrivateRoomRepository()),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('it'),
          home: AuthWrapper(),
        ),
      );

  testWidgets('shows the welcome screen when signed out', (tester) async {
    await tester.pumpWidget(buildApp(FakeAuthRepository()));

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets(
      'follows the auth state: home when signed in, welcome after '
      'signing out', (tester) async {
    final auth = FakeAuthRepository(email: 'luca@example.com');
    await tester.pumpWidget(buildApp(auth));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);

    await auth.signOut();
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });
}
