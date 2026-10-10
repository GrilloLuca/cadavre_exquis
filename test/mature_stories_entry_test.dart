import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/screens/age_check_screen.dart';
import 'package:cadavre_exquisite/screens/complete_stories_screen.dart';
import 'package:cadavre_exquisite/services/age_check_service.dart';
import 'package:cadavre_exquisite/services/age_gate.dart';
import 'package:cadavre_exquisite/services/age_signals_source.dart';
import 'package:cadavre_exquisite/services/story_service.dart';

/// An [AgeSignalsSource] answering with [_answer] and counting its calls.
class _FakeSource implements AgeSignalsSource {
  _FakeSource(this._answer);

  factory _FakeSource.value(AgeSignal signal) =>
      _FakeSource(() async => signal);

  final Future<AgeSignal> Function() _answer;
  int calls = 0;

  @override
  Future<AgeSignal> check() {
    calls++;
    return _answer();
  }
}

const _email = 'Luca@Example.com';
const _docId = 'luca@example.com';
const _adultYear = 1990;
const _minorYear = 2015;

void main() {
  late FakeFirebaseFirestore firestore;
  late AgeCheckService storage;
  late AppLocalizations l10n;

  setUp(() async {
    AgeGate.clearSessionCache();
    CompleteStoriesScreen.clearSessionState();
    firestore = FakeFirebaseFirestore();
    storage = AgeCheckService(firestore: firestore);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  Future<void> seedBirthYear(int year) =>
      firestore.collection('ageChecks').doc(_docId).set({'birthYear': year});

  Future<int?> storedYear() async =>
      (await firestore.collection('ageChecks').doc(_docId).get())
          .data()?['birthYear'] as int?;

  Future<void> pumpScreen(WidgetTester tester, _FakeSource source) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: CompleteStoriesScreen(
          language: 'en',
          storyService: StoryService(firestore: firestore),
          ageGate: AgeGate(signals: source, storage: storage),
          ageCheckService: storage,
          email: _email,
        ),
      ),
    );
    // Let the story stream and the quiet birth-year read settle.
    await tester.pumpAndSettle();
  }

  Finder entry() => find.text(l10n.matureStoriesEntrySubtitle);

  /// The mature list is open once its own empty state is shown.
  Finder matureList() => find.text(l10n.noMatureStories);

  testWidgets('adult signal opens the mature list without the age screen',
      (tester) async {
    final source = _FakeSource.value(AgeSignal.adult);
    await pumpScreen(tester, source);

    await tester.tap(entry());
    await tester.pumpAndSettle();

    expect(find.byType(AgeCheckScreen), findsNothing);
    expect(matureList(), findsOneWidget);
    expect(source.calls, 1);
    expect(await storedYear(), isNull);
  });

  testWidgets('minor signal shows the snackbar and hides the entry',
      (tester) async {
    final source = _FakeSource.value(AgeSignal.minor);
    await pumpScreen(tester, source);
    expect(entry(), findsOneWidget);

    await tester.tap(entry());
    await tester.pumpAndSettle();

    expect(find.byType(AgeCheckScreen), findsNothing);
    expect(matureList(), findsNothing);
    expect(find.text(l10n.matureStoriesUnavailable), findsOneWidget);
    expect(entry(), findsNothing);
    expect(await storedYear(), isNull);
  });

  testWidgets('minor stays hidden when the list is rebuilt this session',
      (tester) async {
    final source = _FakeSource.value(AgeSignal.minor);
    await pumpScreen(tester, source);
    await tester.tap(entry());
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester, source);

    expect(entry(), findsNothing);
  });

  testWidgets(
      'unavailable signal with no stored year asks, stores and opens the list',
      (tester) async {
    final source = _FakeSource.value(AgeSignal.unavailable);
    await pumpScreen(tester, source);

    await tester.tap(entry());
    await tester.pumpAndSettle();
    expect(find.byType(AgeCheckScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(AgeCheckScreen))).pop(_adultYear);
    await tester.pumpAndSettle();

    expect(await storedYear(), _adultYear);
    expect(matureList(), findsOneWidget);
  });

  testWidgets('a minor birth year from the age screen hides the entry',
      (tester) async {
    final source = _FakeSource.value(AgeSignal.unavailable);
    await pumpScreen(tester, source);

    await tester.tap(entry());
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(AgeCheckScreen))).pop(_minorYear);
    await tester.pumpAndSettle();

    expect(await storedYear(), _minorYear);
    expect(matureList(), findsNothing);
    expect(find.text(l10n.matureStoriesUnavailable), findsOneWidget);
    expect(entry(), findsNothing);
  });

  testWidgets(
      'unavailable signal with a stored adult year skips the age screen',
      (tester) async {
    await seedBirthYear(_adultYear);
    final source = _FakeSource.value(AgeSignal.unavailable);
    await pumpScreen(tester, source);

    await tester.tap(entry());
    await tester.pumpAndSettle();

    expect(find.byType(AgeCheckScreen), findsNothing);
    expect(matureList(), findsOneWidget);
  });

  testWidgets('stored minor year hides the entry without asking the platform',
      (tester) async {
    await seedBirthYear(_minorYear);
    final source = _FakeSource.value(AgeSignal.adult);
    await pumpScreen(tester, source);

    expect(entry(), findsNothing);
    expect(source.calls, 0);
  });

  testWidgets('shows a spinner and ignores taps while the check runs',
      (tester) async {
    final answer = Completer<AgeSignal>();
    final source = _FakeSource(() => answer.future);
    await pumpScreen(tester, source);

    await tester.tap(entry());
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    await tester.tap(entry());
    await tester.pump();
    expect(source.calls, 1);

    answer.complete(AgeSignal.adult);
    await tester.pumpAndSettle();
    expect(matureList(), findsOneWidget);
    expect(source.calls, 1);
  });
}
