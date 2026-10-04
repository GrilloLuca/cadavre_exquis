// Basic smoke test: the welcome screen should show the app name and the
// Log In / Register entry points.
//
// Pumps WelcomeScreen directly rather than CadavreExquisiteApp, because the
// app's AuthWrapper requires an initialized Firebase app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/screens/welcome_screen.dart';

void main() {
  testWidgets('Welcome screen shows app name and auth buttons',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: WelcomeScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Cadavre Exquisite'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
  });
}
