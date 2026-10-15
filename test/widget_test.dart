// Basic smoke tests: the welcome screen should show the app name and the
// Google sign-in button, and the home screen should not build its story
// tabs before it knows the language room.
//
// Pumps the screens directly rather than CadavreExquisiteApp, because the
// app's AuthWrapper requires an initialized Firebase app.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/notification/notification_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';

import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/home/widgets/home_screen.dart';
import 'package:cadavre_exquisite/ui/auth/widgets/welcome_screen.dart';
import 'package:cadavre_exquisite/data/repositories/room/room_repository.dart';

import '../testing/fakes/repositories/fake_age_check_repository.dart';
import '../testing/fakes/repositories/fake_auth_repository.dart';
import '../testing/fakes/repositories/fake_notification_repository.dart';
import '../testing/fakes/repositories/fake_room_repository.dart';
import '../testing/fakes/repositories/fake_story_repository.dart';

void main() {
  testWidgets('Welcome screen shows the Google sign-in button',
      (WidgetTester tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<AuthRepository>(
      create: (_) => FakeAuthRepository(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: WelcomeScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('Home screen waits for the language room before the stories',
      (WidgetTester tester) async {
    // The stored room is still being read.
    final stillLoading = Completer<void>();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthRepository>(
            create: (_) => FakeAuthRepository(email: 'me@example.com')),
        ChangeNotifierProvider<RoomRepository>(
            create: (_) =>
                FakeRoomRepository(pendingLoad: stillLoading.future)),
        Provider<StoryRepository>(create: (_) => FakeStoryRepository()),
        Provider<AgeGate>(
            create: (_) => AgeGate(storage: FakeAgeCheckRepository())),
        ChangeNotifierProvider<NotificationRepository>(
            create: (_) => FakeNotificationRepository()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const HomeScreen(),
      ),
    ));
    await tester.pump();

    expect(find.text('Incomplete stories'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(IndexedStack), findsNothing);
    // The room menu is gone, and the indicator waits for the room too.
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
  });
}
