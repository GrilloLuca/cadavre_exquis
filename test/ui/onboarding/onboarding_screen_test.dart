import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/onboarding/onboarding_repository.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/onboarding/widgets/onboarding_screen.dart';

import '../../../testing/fakes/repositories/fake_onboarding_repository.dart';

void main() {
  Widget buildScreen(FakeOnboardingRepository onboarding) =>
      ChangeNotifierProvider<OnboardingRepository>.value(
        value: onboarding,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: OnboardingScreen(),
        ),
      );

  testWidgets('goes through the three slides and marks them seen on Start',
      (tester) async {
    final onboarding = FakeOnboardingRepository(hasSeen: false);
    await tester.pumpWidget(buildScreen(onboarding));

    expect(find.text('Four authors.\nOne story.'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('You only see five words'), findsOneWidget);
    // The demo shows the five words the next author gets to read.
    expect(find.text('… a tiny, very angry penguin'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Then comes the reveal'), findsOneWidget);
    // The demo ends with every part of the story readable.
    expect(find.text('The detective found a tiny, very angry penguin'),
        findsOneWidget);
    expect(find.text('so they all opened a bakery.'), findsOneWidget);

    expect(find.text('Next'), findsNothing);
    expect(onboarding.markSeenCalls, 0);

    await tester.tap(find.text('Start'));
    await tester.pump();

    expect(onboarding.markSeenCalls, 1);
  });

  testWidgets('Skip marks the slides seen from the first one',
      (tester) async {
    final onboarding = FakeOnboardingRepository(hasSeen: false);
    await tester.pumpWidget(buildScreen(onboarding));

    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(onboarding.markSeenCalls, 1);
  });
}
