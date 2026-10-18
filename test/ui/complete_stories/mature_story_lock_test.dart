import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/ui/complete_stories/widgets/age_check_screen.dart';
import 'package:cadavre_exquisite/ui/complete_stories/widgets/complete_stories_screen.dart';
import 'package:cadavre_exquisite/ui/story_read/widgets/story_read_screen.dart';
import 'package:cadavre_exquisite/data/repositories/age_check/age_check_repository.dart';
import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/age_check/age_check_repository_firestore.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/data/services/age_signals_source.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository_firestore.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository_firestore.dart';

import '../../../testing/fakes/repositories/fake_auth_repository.dart';

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

/// An [AgeGate] whose quiet stored-birth-year read waits for [read].
class _DelayedReadGate extends AgeGate {
  _DelayedReadGate(this.read, {required super.signals, required super.storage});

  final Future<int?> read;

  @override
  Future<int?> storedBirthYear(String email) => read;
}

/// An [AgeGate] whose [resolve] always fails.
class _FailingGate extends AgeGate {
  _FailingGate({required super.signals, required super.storage});

  @override
  Future<AgeVerdict> resolve(String email) async =>
      throw StateError('gate failure');
}

const _email = 'Luca@Example.com';
const _docId = 'luca@example.com';
const _adultYear = 1990;
const _minorYear = 2015;

// Mature stories: their texts must never leak while locked; their
// (child-safe) AI titles are shown, but not to known minors.
const _matureNewTitle = 'Spicy newest title';
const _matureNewText = 'spicy newest first part';
const _matureOldTitle = 'Spicy older title';
const _matureOldText = 'spicy older first part';
const _normalTitle = 'A gentle story';
const _unreviewedTitle = 'Not reviewed yet';

void main() {
  late FakeFirebaseFirestore firestore;
  late AgeCheckRepository storage;
  late AppLocalizations l10n;
  late FakeAuthRepository auth;

  /// The gate the screen gets when a test doesn't pass its own: one per
  /// test, shared across pumps like the app's single gate.
  AgeGate? sharedGate;

  Future<void> addStory(
    String id, {
    required String? title,
    required int seconds,
    bool? mature = false,
    String firstText = 'first part',
    String firstAuthor = 'someone@example.com',
    String language = 'en',
    String? roomId,
  }) {
    return firestore.collection('stories').doc(id).set({
      'status': 'complete',
      'currentPosition': 'epilogo',
      'title': title,
      'parts': [
        {
          'position': kStoryPositions[0],
          'text': firstText,
          'author': firstAuthor,
          'timestamp': Timestamp.fromMillisecondsSinceEpoch(seconds * 1000),
        },
      ],
      'lockedBy': null,
      'language': language,
      'roomId': roomId,
      if (mature != null) 'mature': mature,
    });
  }

  setUp(() async {
    sharedGate = null;
    auth = FakeAuthRepository(email: _email);
    firestore = FakeFirebaseFirestore();
    storage = AgeCheckRepositoryFirestore(firestore: firestore);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Service order (newest completed first): mature-new, normal,
    // mature-old. The unreviewed story is never listed.
    await addStory('mature-new',
        title: _matureNewTitle,
        seconds: 300,
        mature: true,
        firstText: _matureNewText);
    await addStory('normal', title: _normalTitle, seconds: 200);
    await addStory('mature-old',
        title: _matureOldTitle,
        seconds: 100,
        mature: true,
        firstText: _matureOldText);
    await addStory('unreviewed',
        title: _unreviewedTitle, seconds: 400, mature: null);
  });

  Future<void> seedBirthYear(int year) =>
      firestore.collection('ageChecks').doc(_docId).set({'birthYear': year});

  Future<int?> storedYear() async =>
      (await firestore.collection('ageChecks').doc(_docId).get())
          .data()?['birthYear'] as int?;

  /// The screen in an app, signed in as [_email]. Without [gate] it uses
  /// [sharedGate], so what the session remembers survives re-pumps as in
  /// the app. Re-pumping with another room or language exercises
  /// `didUpdateWidget` rather than a fresh state.
  Widget app(
    _FakeSource source, {
    AgeGate? gate,
    StoryRepository? storyRepository,
    String language = 'en',
    String? roomId,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthRepository>.value(value: auth),
        Provider<StoryRepository>.value(
          value:
              storyRepository ?? StoryRepositoryFirestore(firestore: firestore),
        ),
        Provider<AgeGate>.value(
          value: gate ??
              (sharedGate ??= AgeGate(
                signals: source,
                storage: storage,
                authRepository: auth,
              )),
        ),
        Provider<UserProfileRepository>.value(
          value: UserProfileRepositoryFirestore(firestore: firestore),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: CompleteStoriesScreen(language: language, roomId: roomId),
      ),
    );
  }

  /// What the sign-out button does, then signing back in as the same user.
  Future<void> signOutAndIn() async {
    await auth.signOut();
    await auth.signInWithEmail(email: _email, password: 'secret');
  }

  Future<void> pumpScreen(WidgetTester tester, _FakeSource source,
      {AgeGate? gate}) async {
    await tester.pumpWidget(app(source, gate: gate));
    // Let the story stream and the quiet birth-year read settle.
    await tester.pumpAndSettle();
  }

  Finder locked() => find.byIcon(Icons.lock);
  Finder lockIcons() => find.byIcon(Icons.lock);
  Finder unavailable() => find.text(l10n.matureStoryUnavailable);

  /// Id of the story open in [StoryReadScreen], or null if none is open.
  String? openStoryId(WidgetTester tester) {
    final screens = find.byType(StoryReadScreen);
    if (screens.evaluate().isEmpty) return null;
    return tester.widget<StoryReadScreen>(screens).story.id;
  }

  Future<void> goBack(WidgetTester tester) async {
    Navigator.of(tester.element(find.byType(StoryReadScreen))).pop();
    await tester.pumpAndSettle();
  }

  /// No part text of a mature story is on screen.
  void expectNoMatureContent() {
    for (final text in [_matureNewText, _matureOldText]) {
      expect(find.text(text), findsNothing, reason: text);
    }
  }

  /// Nothing at all of a mature story is on screen, title included.
  void expectNoMatureStories() {
    expectNoMatureContent();
    for (final text in [_matureNewTitle, _matureOldTitle]) {
      expect(find.text(text), findsNothing, reason: text);
    }
  }

  testWidgets(
      'mature stories are inline and locked, in the service order, '
      'with their title but no text and no adult section', (tester) async {
    final source = _FakeSource.value(AgeSignal.adult);
    await pumpScreen(tester, source);

    expect(locked(), findsNWidgets(2));
    expect(lockIcons(), findsNWidgets(2));
    expect(find.text(l10n.authorsCount(1)), findsOneWidget);
    expect(
      find.text('${l10n.matureStoryLockedTitle} · ${l10n.authorsCount(1)}'),
      findsNWidgets(2),
    );
    expect(find.text(_matureNewTitle), findsOneWidget);
    expect(find.text(_matureOldTitle), findsOneWidget);
    expectNoMatureContent();
    expect(find.text(_normalTitle), findsOneWidget);
    expect(find.text(_unreviewedTitle), findsNothing);

    // Newest first: locked (300), normal (200), locked (100).
    final lockedY = [
      for (var i = 0; i < 2; i++) tester.getTopLeft(locked().at(i)).dy,
    ];
    final normalY = tester.getTopLeft(find.text(_normalTitle)).dy;
    expect(lockedY[0], lessThan(normalY));
    expect(lockedY[1], greaterThan(normalY));

    // Same tile size as a normal story.
    final tiles = find.byType(ListTile);
    final sizes = tiles.evaluate().map((e) => e.size!.height).toSet();
    expect(sizes, hasLength(1));

    // No separate section and no entry for it.
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(find.textContaining('Stories for adults'), findsNothing);
    expect(source.calls, 0);
  });

  testWidgets('locked tile has the padlock label and the unlock hint',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(tester, _FakeSource.value(AgeSignal.adult));

    final icon = tester.widget<Icon>(lockIcons().first);
    expect(icon.semanticLabel, l10n.matureStoryLockedLabel);
    expect(icon.size, 24.0);
    // ListTile merges its children: the screen reader gets the title, the
    // explicit-content label, "locked" and the "unlock" hint together.
    final data = tester.getSemantics(locked().first).getSemanticsData();
    expect(data.label, contains(_matureNewTitle));
    expect(data.label, contains(l10n.matureStoryLockedTitle));
    expect(data.label, contains(l10n.authorsCount(1)));
    expect(data.label, contains(l10n.matureStoryLockedLabel));
    expect(
      find.ancestor(
        of: locked().first,
        matching: find.byWidgetPredicate((w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.hintOverrides?.onTapHint ==
                l10n.matureStoryUnlockHint),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets(
      'adult signal opens the tapped story and unlocks every mature story '
      'for the session', (tester) async {
    final source = _FakeSource.value(AgeSignal.adult);
    await pumpScreen(tester, source);

    await tester.tap(locked().first);
    await tester.pumpAndSettle();

    expect(find.byType(AgeCheckScreen), findsNothing);
    expect(openStoryId(tester), 'mature-new');
    expect(source.calls, 1);
    expect(await storedYear(), isNull);

    await goBack(tester);
    expect(locked(), findsNothing);
    expect(lockIcons(), findsNothing);
    expect(find.text(_matureNewTitle), findsOneWidget);
    expect(find.text(_matureOldTitle), findsOneWidget);
    final openLocks = find.byIcon(Icons.lock_open);
    expect(openLocks, findsNWidgets(2));
    expect(tester.widget<Icon>(openLocks.first).semanticLabel,
        l10n.matureStoryAdultContent);

    await tester.tap(find.text(_matureOldTitle));
    await tester.pumpAndSettle();
    expect(openStoryId(tester), 'mature-old');
    expect(source.calls, 1);
    await goBack(tester);

    // Still unlocked when the list is built from scratch.
    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester, source);
    expect(locked(), findsNothing);
    await tester.tap(find.text(_matureNewTitle));
    await tester.pumpAndSettle();
    expect(openStoryId(tester), 'mature-new');
    expect(source.calls, 1);
  });

  testWidgets('signing out locks mature stories again', (tester) async {
    final source = _FakeSource.value(AgeSignal.adult);
    await pumpScreen(tester, source);
    await tester.tap(locked().first);
    await tester.pumpAndSettle();
    await goBack(tester);
    expect(locked(), findsNothing);

    await signOutAndIn();
    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester, source);
    expect(locked(), findsNWidgets(2));
    expectNoMatureContent();
  });

  testWidgets(
      'unavailable signal with no stored year asks, stores and opens the story',
      (tester) async {
    final source = _FakeSource.value(AgeSignal.unavailable);
    await pumpScreen(tester, source);

    await tester.tap(locked().last);
    await tester.pumpAndSettle();
    expect(find.byType(AgeCheckScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(AgeCheckScreen))).pop(_adultYear);
    await tester.pumpAndSettle();

    expect(await storedYear(), _adultYear);
    expect(find.byType(AgeCheckScreen), findsNothing);
    expect(openStoryId(tester), 'mature-old');
  });

  testWidgets(
      'a minor birth year from the age screen shows the snackbar and hides '
      'mature stories', (tester) async {
    final source = _FakeSource.value(AgeSignal.unavailable);
    await pumpScreen(tester, source);

    await tester.tap(locked().first);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(AgeCheckScreen))).pop(_minorYear);
    await tester.pumpAndSettle();

    expect(await storedYear(), _minorYear);
    expect(openStoryId(tester), isNull);
    expect(unavailable(), findsOneWidget);
    expect(locked(), findsNothing);
    expect(lockIcons(), findsNothing);
    expectNoMatureStories();
    expect(find.text(_normalTitle), findsOneWidget);
  });

  testWidgets('back from the age screen without answering does nothing',
      (tester) async {
    final source = _FakeSource.value(AgeSignal.unavailable);
    await pumpScreen(tester, source);

    await tester.tap(locked().first);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(AgeCheckScreen))).pop();
    await tester.pumpAndSettle();

    expect(await storedYear(), isNull);
    expect(find.byType(SnackBar), findsNothing);
    expect(openStoryId(tester), isNull);
    expect(locked(), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'minor signal shows the snackbar once and hides mature stories for the '
      'session', (tester) async {
    final source = _FakeSource.value(AgeSignal.minor);
    await pumpScreen(tester, source);

    await tester.tap(locked().first);
    await tester.pumpAndSettle();

    expect(find.byType(AgeCheckScreen), findsNothing);
    expect(openStoryId(tester), isNull);
    expect(unavailable(), findsOneWidget);
    expect(locked(), findsNothing);
    expect(find.text(_normalTitle), findsOneWidget);
    expect(await storedYear(), isNull);

    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester, source);
    expect(locked(), findsNothing);
    expect(find.text(_normalTitle), findsOneWidget);
    expect(source.calls, 1);
  });

  testWidgets(
      'stored minor year hides mature stories without asking the platform',
      (tester) async {
    await seedBirthYear(_minorYear);
    final source = _FakeSource.value(AgeSignal.adult);
    await pumpScreen(tester, source);

    expect(locked(), findsNothing);
    expect(lockIcons(), findsNothing);
    expectNoMatureStories();
    expect(find.text(_normalTitle), findsOneWidget);
    expect(source.calls, 0);
  });

  testWidgets(
      'stored minor year with only mature stories shows the empty state',
      (tester) async {
    await firestore.collection('stories').doc('normal').delete();
    await seedBirthYear(_minorYear);
    final source = _FakeSource.value(AgeSignal.adult);
    await pumpScreen(tester, source);

    expect(find.text(l10n.noCompleteStories), findsOneWidget);
    expect(locked(), findsNothing);
    expect(find.byType(ListTile), findsNothing);
    expect(source.calls, 0);
  });

  testWidgets(
      'stored adult year with an unavailable signal opens without the age '
      'screen', (tester) async {
    await seedBirthYear(_adultYear);
    final source = _FakeSource.value(AgeSignal.unavailable);
    await pumpScreen(tester, source);

    // Not unlocked up front: the signal may still say minor.
    expect(locked(), findsNWidgets(2));

    await tester.tap(locked().first);
    await tester.pumpAndSettle();

    expect(find.byType(AgeCheckScreen), findsNothing);
    expect(openStoryId(tester), 'mature-new');
  });

  testWidgets('a gate error shows the generic error and stays locked',
      (tester) async {
    final source = _FakeSource.value(AgeSignal.adult);
    await pumpScreen(tester, source,
        gate: _FailingGate(signals: source, storage: storage));

    await tester.tap(locked().first);
    await tester.pumpAndSettle();

    expect(find.text(l10n.genericError), findsOneWidget);
    expect(openStoryId(tester), isNull);
    expect(locked(), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'shows a spinner on the tapped story and ignores taps while the check '
      'runs', (tester) async {
    final answer = Completer<AgeSignal>();
    final source = _FakeSource(() => answer.future);
    await pumpScreen(tester, source);

    await tester.tap(locked().first);
    await tester.pump();
    final spinner = find.descendant(
      of: find.byType(ListTile),
      matching: find.byType(CircularProgressIndicator),
    );
    expect(spinner, findsOneWidget);
    expect(tester.getSize(spinner), const Size(18.0, 18.0));
    // The spinner is in the tapped (first) tile.
    expect(
      find.descendant(
        of: find.ancestor(of: locked().first, matching: find.byType(ListTile)),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    await tester.tap(locked().first);
    await tester.tap(locked().last);
    await tester.pump();
    expect(source.calls, 1);
    expect(find.byType(StoryReadScreen), findsNothing);

    answer.complete(AgeSignal.adult);
    await tester.pumpAndSettle();
    expect(openStoryId(tester), 'mature-new');
    expect(find.byType(StoryReadScreen), findsOneWidget);
    expect(source.calls, 1);
  });

  testWidgets('a locked story with no title shows the explicit-content label',
      (tester) async {
    // A story the model refused to read is mature with no title.
    await addStory('untitled-mature',
        title: null,
        seconds: 50,
        mature: true,
        firstText: 'untitled spicy part');
    await pumpScreen(tester, _FakeSource.value(AgeSignal.adult));

    expect(locked(), findsNWidgets(3));
    expect(find.text(l10n.matureStoryLockedTitle), findsOneWidget);
    expect(find.text('untitled spicy part'), findsNothing);
    expectNoMatureContent();
  });

  testWidgets('a mature story the user co-wrote is in their tab, still locked',
      (tester) async {
    await addStory('mine-mature',
        title: 'My spicy story',
        seconds: 50,
        mature: true,
        firstText: 'my spicy part',
        firstAuthor: _email);
    await pumpScreen(tester, _FakeSource.value(AgeSignal.adult));

    // Everyone else's stories show first; the user's are a tab away.
    expect(find.text('My spicy story'), findsNothing);
    expect(locked(), findsNWidgets(2));

    await tester.tap(find.text(l10n.yourStoriesHeading));
    await tester.pumpAndSettle();
    expect(find.text('My spicy story'), findsOneWidget);
    expect(find.text('my spicy part'), findsNothing);
    expect(find.text(_normalTitle), findsNothing);
    expect(locked(), findsOneWidget);
  });

  group('tabs', () {
    /// Adds [count] stories by the user, "Mine 0" the newest, older than
    /// every story from setUp.
    Future<void> addMine(int count) async {
      for (var i = 0; i < count; i++) {
        await addStory('mine-$i',
            title: 'Mine $i', seconds: 90 - i, firstAuthor: _email);
      }
    }

    double topOf(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text)).dy;

    testWidgets('a single list per tab, keeping its scroll offset',
        (tester) async {
      await addMine(15);
      await pumpScreen(tester, _FakeSource.value(AgeSignal.adult));

      expect(find.byType(ListView), findsOneWidget);
      expect(find.text('Mine 0'), findsNothing);

      await tester.tap(find.text(l10n.yourStoriesHeading));
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsOneWidget);
      expect(find.text(_normalTitle), findsNothing);
      expect(find.text('Mine 0'), findsOneWidget);

      await tester.drag(find.text('Mine 1'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('Mine 0'), findsNothing);
      final mineTop = topOf(tester, 'Mine 6');

      // Back and forth: the user's list is where they left it.
      await tester.tap(find.text(l10n.otherStoriesTab));
      await tester.pumpAndSettle();
      expect(find.text(_normalTitle), findsOneWidget);
      await tester.tap(find.text(l10n.yourStoriesHeading));
      await tester.pumpAndSettle();
      expect(topOf(tester, 'Mine 6'), mineTop);
    },
        variant: TargetPlatformVariant(
            {TargetPlatform.android, TargetPlatform.iOS}));

    testWidgets('a user without completed stories is told so in their tab',
        (tester) async {
      await pumpScreen(tester, _FakeSource.value(AgeSignal.adult));

      await tester.tap(find.text(l10n.yourStoriesHeading));
      await tester.pumpAndSettle();
      expect(find.text(l10n.noYourCompleteStories), findsOneWidget);
    });

    testWidgets('opens on the user\'s tab when only that one has stories',
        (tester) async {
      await firestore.collection('stories').get().then((snapshot) async {
        for (final doc in snapshot.docs) {
          await doc.reference.delete();
        }
      });
      await addMine(1);
      await pumpScreen(tester, _FakeSource.value(AgeSignal.adult));

      expect(find.text('Mine 0'), findsOneWidget);
      expect(find.text(l10n.noOtherCompleteStories), findsNothing);
    });
  });

  group('slow stored birth-year read', () {
    /// Pumps single frames (never settles) while the read is pending, and
    /// checks that no locked tile is shown in any of them.
    Future<void> pumpFramesWithoutLockedTiles(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(locked(), findsNothing, reason: 'frame $i');
        expect(lockIcons(), findsNothing, reason: 'frame $i');
        expectNoMatureStories();
      }
    }

    testWidgets('a stored minor never sees a locked tile', (tester) async {
      await seedBirthYear(_minorYear);
      final read = Completer<int?>();
      final source = _FakeSource.value(AgeSignal.adult);
      await tester.pumpWidget(app(source,
          gate: _DelayedReadGate(read.future,
              signals: source, storage: storage)));
      expect(locked(), findsNothing);

      await pumpFramesWithoutLockedTiles(tester);
      // Normal stories don't wait for the read.
      expect(find.text(_normalTitle), findsOneWidget);

      read.complete(_minorYear);
      await tester.pump();
      expect(locked(), findsNothing);
      await pumpFramesWithoutLockedTiles(tester);
      await tester.pumpAndSettle();
      expect(locked(), findsNothing);
      expect(find.text(_normalTitle), findsOneWidget);
      expect(source.calls, 0);
    });

    testWidgets('locked tiles appear once the read finds no minor',
        (tester) async {
      final read = Completer<int?>();
      final source = _FakeSource.value(AgeSignal.adult);
      await tester.pumpWidget(app(source,
          gate: _DelayedReadGate(read.future,
              signals: source, storage: storage)));

      await pumpFramesWithoutLockedTiles(tester);
      expect(find.text(_normalTitle), findsOneWidget);

      read.complete(null);
      await tester.pumpAndSettle();
      expect(locked(), findsNWidgets(2));
      expect(find.text(_normalTitle), findsOneWidget);
      expectNoMatureContent();
    });

    testWidgets('locked tiles appear when the read fails', (tester) async {
      final read = Completer<int?>();
      final source = _FakeSource.value(AgeSignal.adult);
      await tester.pumpWidget(app(source,
          gate: _DelayedReadGate(read.future,
              signals: source, storage: storage)));
      await pumpFramesWithoutLockedTiles(tester);

      read.completeError(StateError('read failure'));
      await tester.pumpAndSettle();
      expect(locked(), findsNWidgets(2));
      expect(find.text(_normalTitle), findsOneWidget);
    });
  });

  group('room or language change', () {
    const otherRoomTitle = 'A private room story';
    const otherRoomMatureTitle = 'Spicy private room title';
    const italianTitle = 'Una storia italiana';

    setUp(() async {
      await addStory('room-normal',
          title: otherRoomTitle, seconds: 500, roomId: 'room-1');
      await addStory('room-mature',
          title: otherRoomMatureTitle,
          seconds: 600,
          mature: true,
          roomId: 'room-1');
      await addStory('it-normal',
          title: italianTitle, seconds: 700, language: 'it');
    });

    testWidgets('re-pumping with another room or language swaps the list',
        (tester) async {
      final source = _FakeSource.value(AgeSignal.adult);
      final service = StoryRepositoryFirestore(firestore: firestore);
      final gate = AgeGate(signals: source, storage: storage);

      await tester
          .pumpWidget(app(source, gate: gate, storyRepository: service));
      await tester.pumpAndSettle();
      expect(find.text(_normalTitle), findsOneWidget);
      expect(find.text(otherRoomTitle), findsNothing);
      expect(find.text(italianTitle), findsNothing);
      expect(locked(), findsNWidgets(2));

      await tester.pumpWidget(
          app(source, gate: gate, storyRepository: service, roomId: 'room-1'));
      await tester.pumpAndSettle();
      expect(find.text(otherRoomTitle), findsOneWidget);
      expect(find.text(_normalTitle), findsNothing);
      expect(locked(), findsOneWidget);
      expect(find.text(otherRoomMatureTitle), findsOneWidget);

      await tester.pumpWidget(
          app(source, gate: gate, storyRepository: service, language: 'it'));
      await tester.pumpAndSettle();
      expect(find.text(italianTitle), findsOneWidget);
      expect(find.text(_normalTitle), findsNothing);
      expect(find.text(otherRoomTitle), findsNothing);
      expect(locked(), findsNothing);
    });

    testWidgets('an adult unlock persists across a room change',
        (tester) async {
      final source = _FakeSource.value(AgeSignal.adult);
      final service = StoryRepositoryFirestore(firestore: firestore);
      final gate = AgeGate(signals: source, storage: storage);

      await tester
          .pumpWidget(app(source, gate: gate, storyRepository: service));
      await tester.pumpAndSettle();
      await tester.tap(locked().first);
      await tester.pumpAndSettle();
      expect(openStoryId(tester), 'mature-new');
      await goBack(tester);

      await tester.pumpWidget(
          app(source, gate: gate, storyRepository: service, roomId: 'room-1'));
      await tester.pumpAndSettle();
      expect(locked(), findsNothing);
      expect(find.text(otherRoomMatureTitle), findsOneWidget);
      await tester.tap(find.text(otherRoomMatureTitle));
      await tester.pumpAndSettle();
      expect(openStoryId(tester), 'room-mature');
      expect(source.calls, 1);
    });
  });

  testWidgets('signing out locks again and asks the platform afresh',
      (tester) async {
    final source = _FakeSource.value(AgeSignal.adult);
    await pumpScreen(tester, source);
    await tester.tap(locked().first);
    await tester.pumpAndSettle();
    await goBack(tester);
    expect(locked(), findsNothing);
    expect(source.calls, 1);

    await signOutAndIn();

    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester, source);
    expect(locked(), findsNWidgets(2));
    expectNoMatureContent();

    // The cached adult signal is gone too: the next tap asks again.
    await tester.tap(locked().first);
    await tester.pumpAndSettle();
    expect(openStoryId(tester), 'mature-new');
    expect(source.calls, 2);
  });

  testWidgets('signing out also forgets a session minor', (tester) async {
    final source = _FakeSource.value(AgeSignal.minor);
    await pumpScreen(tester, source);
    await tester.tap(locked().first);
    await tester.pumpAndSettle();
    expect(locked(), findsNothing);

    await signOutAndIn();

    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester, source);
    expect(locked(), findsNWidgets(2));
  });
}
