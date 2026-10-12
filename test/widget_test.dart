// Basic smoke tests: the welcome screen should show the app name and the
// Google sign-in button, and the home screen should not build its story
// tabs before it knows the language room.
//
// Pumps the screens directly rather than CadavreExquisiteApp, because the
// app's AuthWrapper requires an initialized Firebase app.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/screens/home_screen.dart';
import 'package:cadavre_exquisite/screens/welcome_screen.dart';
import 'package:cadavre_exquisite/services/language_room_preference.dart';

/// A preference whose stored room is still being read.
class _PendingPreference extends LanguageRoomPreference {
  _PendingPreference() : super(deviceLocales: () => const []);

  final _resolved = Completer<({String code, RoomLanguageSource source})>();

  @override
  Future<({String code, RoomLanguageSource source})> resolveWithSource() =>
      _resolved.future;
}

void main() {
  testWidgets('Welcome screen shows the Google sign-in button',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: WelcomeScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('Home screen waits for the language room before the stories',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: HomeScreen(languageRoomPreference: _PendingPreference()),
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
