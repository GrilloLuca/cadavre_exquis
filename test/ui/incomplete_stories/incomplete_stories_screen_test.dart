import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/notification/notification_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/data/services/age_signals_source.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/models/app_config.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/chat/widgets/chat_screen.dart';
import 'package:cadavre_exquisite/ui/complete_stories/widgets/age_check_screen.dart';
import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/ui/typing_indicator.dart';
import 'package:cadavre_exquisite/ui/incomplete_stories/widgets/incomplete_stories_screen.dart';

import '../../../testing/fakes/repositories/fake_age_check_repository.dart';
import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_notification_repository.dart';
import '../../../testing/fakes/repositories/fake_story_repository.dart';
import '../../../testing/fakes/repositories/fake_user_profile_repository.dart';

const _me = 'me@example.com';
const _other = 'other@example.com';

/// An [AgeSignalsSource] answering with [_answer].
class _Source implements AgeSignalsSource {
  _Source(this._answer);

  factory _Source.value(AgeSignal signal) => _Source(() async => signal);

  final Future<AgeSignal> Function() _answer;

  @override
  Future<AgeSignal> check() => _answer();
}

/// An [AgeGate] counting its [resolve] calls, whose quiet stored-year read
/// waits for [read] when given.
class _CountingGate extends AgeGate {
  _CountingGate({required super.signals, required super.storage});

  int resolves = 0;
  Future<int?>? read;

  @override
  Future<AgeVerdict> resolve(String email) {
    resolves++;
    return super.resolve(email);
  }

  @override
  Future<int?> storedBirthYear(String email) =>
      read ?? super.storedBirthYear(email);
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  /// A birth year that makes the user a minor today.
  final minorYear = DateTime.now().year - 10;

  /// The last words of every story built by [story]: never on screen
  /// unless the story can be opened without the age check.
  const lastWords = 'the dragon ate the moon';

  /// An incomplete story whose parts were written by [authors], the last
  /// one ending in [lastWords]; with [reviewed] false its last part has no
  /// verdict yet.
  Story story(
    String id, {
    List<String> authors = const [_other],
    bool reviewed = true,
    bool? mature,
    String? lockedBy,
  }) =>
      Story(
        id: id,
        status: 'incomplete',
        currentPosition: kStoryPositions[authors.length],
        parts: [
          for (final (i, author) in authors.indexed)
            StoryPart(
              position: kStoryPositions[i],
              text: 'Once upon a time $lastWords',
              author: author,
              timestamp: DateTime.utc(2026, 10, 1),
            ),
        ],
        lockedBy: lockedBy,
        lockedAt: lockedBy == null ? null : DateTime.now(),
        language: 'it',
        mature: mature,
        partReviews: {
          for (var i = 0; i < authors.length; i++)
            if (reviewed || i < authors.length - 1)
              kStoryPositions[i]: PartVerdict.safe,
        },
      );

  /// [s] once its last part has a verdict, as the server writes it.
  Story withVerdict(Story s, PartVerdict verdict) => Story(
        id: s.id,
        status: s.status,
        currentPosition: s.currentPosition,
        parts: s.parts,
        language: s.language,
        mature: verdict == PartVerdict.mature ? true : s.mature,
        partReviews: {...s.partReviews, s.parts.last.position: verdict},
      );

  late _CountingGate gate;

  /// Pumps the list signed in as [_me], with a gate answering [source]
  /// (adult by default), [birthYears] stored, and an adult verdict this
  /// session if [sessionAdult].
  Future<void> pump(
    WidgetTester tester,
    FakeStoryRepository stories, {
    String? roomId,
    _Source? source,
    Map<String, int> birthYears = const {},
    Future<int?>? read,
    bool sessionAdult = false,
    bool matureVisibleToMinors = true,
  }) async {
    gate = _CountingGate(
      signals: source ?? _Source.value(AgeSignal.adult),
      storage: FakeAgeCheckRepository(birthYears: birthYears),
    )..read = read;
    if (sessionAdult) gate.rememberVerdict(_me, adult: true);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthRepository>(
            create: (_) => FakeAuthRepository(email: _me)),
        Provider<StoryRepository>.value(value: stories),
        ChangeNotifierProvider<NotificationRepository>(
            create: (_) => FakeNotificationRepository()),
        Provider<UserProfileRepository>(
            create: (_) => FakeUserProfileRepository()),
        Provider<AppConfig>.value(
            value:
                AppConfig(matureVisibleToMinors: matureVisibleToMinors)),
        Provider<AgeGate>.value(value: gate),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: IncompleteStoriesScreen(language: 'it', roomId: roomId),
      ),
    ));
    // Not pumpAndSettle: the typing indicator of a locked story animates
    // forever. More frames deliver the first list and the stored year.
    await tester.pump();
    await tester.pump();
  }

  /// Lets a stream event or a finished read reach the screen.
  Future<void> deliver(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  Finder tileOf(String id) => find.descendant(
      of: find.byKey(ValueKey(id)), matching: find.byType(ListTile));

  ListTile listTile(WidgetTester tester, String id) =>
      tester.widget<ListTile>(tileOf(id));

  Finder inTile(String id, Finder finder) =>
      find.descendant(of: find.byKey(ValueKey(id)), matching: finder);

  /// The Semantics wrapper giving a locked tile its unlock hint.
  Finder unlockHint(String id) => find.ancestor(
        of: tileOf(id),
        matching: find.byWidgetPredicate((w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.hintOverrides?.onTapHint ==
                l10n.matureStoryUnlockHint),
      );

  Finder lastWordsText() => find.textContaining(lastWords);

  /// Taps [id]'s tile and checks that nothing opened and the gate wasn't
  /// asked.
  Future<void> expectInert(WidgetTester tester, String id) async {
    expect(listTile(tester, id).enabled, isFalse);
    await tester.tap(tileOf(id), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.byType(AgeCheckScreen), findsNothing);
    expect(gate.resolves, 0);
  }

  testWidgets('shows a message when the room has no stories', (tester) async {
    await pump(tester, FakeStoryRepository());

    expect(find.text(l10n.noIncompleteStories), findsOneWidget);
  });

  testWidgets('a story being written by someone else is disabled',
      (tester) async {
    final stories = FakeStoryRepository(stories: [
      Story(
        id: 's1',
        status: 'incomplete',
        currentPosition: kStoryPositions.first,
        parts: const [],
        lockedBy: 'other@example.com',
        lockedAt: DateTime.now(),
      ),
    ]);
    await pump(tester, stories);

    expect(find.text(l10n.storyBeingWritten), findsOneWidget);
    expect(find.byType(TypingIndicator), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ChatScreen), findsNothing);
  });

  testWidgets('an available story shows its last words and opens the chat',
      (tester) async {
    await pump(tester, FakeStoryRepository(stories: [story('s')]));

    expect(find.text('"...$lastWords"'), findsOneWidget);
    expect(find.byIcon(Icons.edit_note), findsOneWidget);
    expect(find.byIcon(Icons.lock_open), findsNothing);

    await tester.tap(tileOf('s'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
  });

  group('under review', () {
    testWidgets(
        'shows the position, the reason and the hourglass, disabled, without '
        'the last words', (tester) async {
      await pump(
          tester, FakeStoryRepository(stories: [story('s', reviewed: false)]));

      expect(find.text(l10n.positionDevelopment1), findsOneWidget);
      expect(find.text(l10n.storyUnderReview), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
      expect(lastWordsText(), findsNothing);
      await expectInert(tester, 's');
    });

    testWidgets(
        'beats waiting for others for the writer, until the verdict arrives',
        (tester) async {
      final mine = story('s', authors: [_me], reviewed: false);
      final stories = FakeStoryRepository(stories: [mine]);
      await pump(tester, stories);

      expect(find.text(l10n.storyUnderReview), findsOneWidget);
      expect(find.text(l10n.storyWaitingForOthers), findsNothing);

      stories.put(withVerdict(mine, PartVerdict.safe));
      await deliver(tester);

      expect(find.text(l10n.storyUnderReview), findsNothing);
      expect(find.text(l10n.storyWaitingForOthers), findsOneWidget);
    });

    testWidgets('is announced with its reason, as disabled', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
          tester, FakeStoryRepository(stories: [story('s', reviewed: false)]));

      final data = tester.getSemantics(tileOf('s')).getSemanticsData();
      expect(data.label, contains(l10n.positionDevelopment1));
      expect(data.label, contains(l10n.storyUnderReview));
      expect(unlockHint('s'), findsNothing);
      handle.dispose();
    });
  });

  group('mature, unknown age', () {
    testWidgets(
        'a reviewed story is locked: padlock, label, no last words, enabled, '
        'with the unlock hint', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
          tester, FakeStoryRepository(stories: [story('s', mature: true)]));

      final padlock = tester.widget<Icon>(inTile('s', find.byIcon(Icons.lock)));
      expect(padlock.color, AppColors.primaryDark);
      expect(padlock.size, 24.0);
      expect(padlock.semanticLabel, l10n.matureStoryLockedLabel);
      expect(find.text(l10n.matureStoryLockedTitle), findsOneWidget);
      expect(lastWordsText(), findsNothing);
      expect(listTile(tester, 's').enabled, isTrue);
      expect(unlockHint('s'), findsOneWidget);
      handle.dispose();
    });

    testWidgets(
        'being written shows the padlock instead of the typing indicator, '
        'disabled', (tester) async {
      await pump(
          tester,
          FakeStoryRepository(
              stories: [story('s', mature: true, lockedBy: _other)]));

      expect(find.byType(TypingIndicator), findsNothing);
      final padlock = tester.widget<Icon>(inTile('s', find.byIcon(Icons.lock)));
      expect(padlock.color, isNull);
      expect(padlock.semanticLabel, l10n.matureStoryLockedLabel);
      expect(find.text(l10n.storyBeingWritten), findsOneWidget);
      expect(lastWordsText(), findsNothing);
      await expectInert(tester, 's');
    });

    testWidgets('waiting for others shows the padlock, disabled',
        (tester) async {
      await pump(
          tester,
          FakeStoryRepository(stories: [
            story('s', authors: [_other, _me], mature: true)
          ]));

      expect(find.byIcon(Icons.hourglass_empty), findsNothing);
      expect(inTile('s', find.byIcon(Icons.lock)), findsOneWidget);
      expect(find.text(l10n.storyWaitingForOthers), findsOneWidget);
      await expectInert(tester, 's');
    });

    testWidgets('an adult verdict opens the chat', (tester) async {
      await pump(
          tester, FakeStoryRepository(stories: [story('s', mature: true)]));

      await tester.tap(tileOf('s'));
      await tester.pumpAndSettle();

      expect(gate.resolves, 1);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(tester.widget<ChatScreen>(find.byType(ChatScreen)).story.id, 's');
    });

    testWidgets(
        'a minor verdict shows the snackbar once and every mature tile turns '
        'unavailable', (tester) async {
      await pump(
          tester,
          FakeStoryRepository(stories: [
            story('a', mature: true),
            story('b', mature: true, authors: [_other, _other]),
          ]),
          source: _Source.value(AgeSignal.minor));

      await tester.tap(tileOf('a'));
      await tester.pumpAndSettle();

      expect(find.text(l10n.matureStoryUnavailable), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.text(l10n.matureStoryUnavailableLabel), findsNWidgets(2));
      expect(listTile(tester, 'a').enabled, isFalse);
      expect(listTile(tester, 'b').enabled, isFalse);

      // A tap on an unavailable tile asks nothing and shows nothing more.
      await tester.tap(tileOf('b'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(gate.resolves, 1);
      expect(find.text(l10n.matureStoryUnavailable), findsOneWidget);
    });

    testWidgets(
        'shows a spinner on the tapped tile and ignores another locked tile '
        'meanwhile', (tester) async {
      final answer = Completer<AgeSignal>();
      await pump(
          tester,
          FakeStoryRepository(stories: [
            story('a', mature: true),
            story('b', mature: true, authors: [_other, _other]),
          ]),
          source: _Source(() => answer.future));

      await tester.tap(tileOf('a'));
      await tester.pump();
      final spinner = inTile('a', find.byType(CircularProgressIndicator));
      expect(spinner, findsOneWidget);
      expect(tester.getSize(spinner), const Size(18.0, 18.0));
      expect(inTile('b', find.byType(CircularProgressIndicator)), findsNothing);

      await tester.tap(tileOf('b'));
      await tester.pump();
      expect(gate.resolves, 1);

      answer.complete(AgeSignal.adult);
      await tester.pumpAndSettle();
      expect(tester.widget<ChatScreen>(find.byType(ChatScreen)).story.id, 'a');
    });

    testWidgets(
        'no signal asks the birth year; back without answering does '
        'nothing', (tester) async {
      await pump(
          tester, FakeStoryRepository(stories: [story('s', mature: true)]),
          source: _Source.value(AgeSignal.unavailable));

      await tester.tap(tileOf('s'));
      await tester.pumpAndSettle();
      expect(find.byType(AgeCheckScreen), findsOneWidget);

      Navigator.of(tester.element(find.byType(AgeCheckScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(inTile('s', find.byType(CircularProgressIndicator)), findsNothing);
      expect(listTile(tester, 's').enabled, isTrue);
    });

    testWidgets('an adult birth year opens the chat', (tester) async {
      await pump(
          tester, FakeStoryRepository(stories: [story('s', mature: true)]),
          source: _Source.value(AgeSignal.unavailable));

      await tester.tap(tileOf('s'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(AgeCheckScreen))).pop(1990);
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsOneWidget);
    });

    testWidgets('while the stored-year read runs, a mature tile is locked',
        (tester) async {
      final read = Completer<int?>();
      await pump(
          tester, FakeStoryRepository(stories: [story('s', mature: true)]),
          birthYears: {_me: minorYear}, read: read.future);

      expect(find.text(l10n.matureStoryLockedTitle), findsOneWidget);
      expect(find.text(l10n.matureStoryUnavailableLabel), findsNothing);
      expect(listTile(tester, 's').enabled, isTrue);

      read.complete(minorYear);
      await deliver(tester);
      expect(find.text(l10n.matureStoryUnavailableLabel), findsOneWidget);
      expect(listTile(tester, 's').enabled, isFalse);
    });
  });

  group('known minor', () {
    testWidgets(
        'a mature story is unavailable: padlock, label, no last words, '
        'disabled, no hint, never asks the gate', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
          tester, FakeStoryRepository(stories: [story('s', mature: true)]),
          birthYears: {_me: minorYear});

      final padlock = tester.widget<Icon>(inTile('s', find.byIcon(Icons.lock)));
      expect(padlock.color, isNull);
      expect(padlock.semanticLabel, l10n.matureStoryLockedLabel);
      expect(find.text(l10n.matureStoryUnavailableLabel), findsOneWidget);
      expect(find.text(l10n.matureStoryLockedTitle), findsNothing);
      expect(lastWordsText(), findsNothing);
      expect(unlockHint('s'), findsNothing);
      final data = tester.getSemantics(tileOf('s')).getSemanticsData();
      expect(data.label, contains(l10n.matureStoryLockedLabel));
      expect(data.label, contains(l10n.matureStoryUnavailableLabel));
      await expectInert(tester, 's');
      handle.dispose();
    });

    testWidgets('unavailable beats under review', (tester) async {
      await pump(
          tester,
          FakeStoryRepository(stories: [
            story('s', mature: true, authors: [_other, _other], reviewed: false)
          ]),
          birthYears: {_me: minorYear});

      expect(find.text(l10n.matureStoryUnavailableLabel), findsOneWidget);
      expect(find.text(l10n.storyUnderReview), findsNothing);
      expect(find.byIcon(Icons.hourglass_top), findsNothing);
      await expectInert(tester, 's');
    });

    testWidgets(
        'their own flagged introduction does not block a new story, and the '
        'list is not empty', (tester) async {
      final stories = FakeStoryRepository(stories: [
        story('mine', authors: [_me], mature: true)
      ]);
      await pump(tester, stories, birthYears: {_me: minorYear});

      expect(find.text(l10n.matureStoryUnavailableLabel), findsOneWidget);
      expect(find.text(l10n.noIncompleteStories), findsNothing);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text(l10n.newStoryBlocked), findsNothing);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(stories.stories, hasLength(2));
    });
  });

  testWidgets(
      'a session adult sees the last words and the open padlock, and opens '
      'the chat without the gate', (tester) async {
    await pump(tester, FakeStoryRepository(stories: [story('s', mature: true)]),
        sessionAdult: true);

    expect(find.text('"...$lastWords"'), findsOneWidget);
    final open = tester.widget<Icon>(find.byIcon(Icons.lock_open));
    expect(open.size, 20.0);
    expect(open.semanticLabel, l10n.matureStoryAdultContent);
    expect(find.byIcon(Icons.lock), findsNothing);

    await tester.tap(tileOf('s'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(gate.resolves, 0);
  });

  testWidgets(
      'the live stream turns in review into available, locked or unavailable '
      'in place', (tester) async {
    final safe = story('safe', reviewed: false);
    final flagged =
        story('flagged', authors: [_other, _other], reviewed: false);
    final stories = FakeStoryRepository(stories: [safe, flagged]);
    await pump(tester, stories);
    final state = tester.state(find.byType(IncompleteStoriesScreen));
    expect(find.text(l10n.storyUnderReview), findsNWidgets(2));

    stories.put(withVerdict(safe, PartVerdict.safe));
    stories.put(withVerdict(flagged, PartVerdict.mature));
    await deliver(tester);

    expect(find.text(l10n.storyUnderReview), findsNothing);
    expect(inTile('safe', find.text('"...$lastWords"')), findsOneWidget);
    expect(inTile('flagged', find.text(l10n.matureStoryLockedTitle)),
        findsOneWidget);
    expect(tester.state(find.byType(IncompleteStoriesScreen)), same(state));

    // For a known minor the flagged story turns unavailable.
    final minorFlagged =
        story('minor', authors: [_other, _other], reviewed: false);
    final minorStories = FakeStoryRepository(stories: [minorFlagged]);
    await tester.pumpWidget(const SizedBox());
    await pump(tester, minorStories, birthYears: {_me: minorYear});
    expect(find.text(l10n.storyUnderReview), findsOneWidget);

    minorStories.put(withVerdict(minorFlagged, PartVerdict.mature));
    await deliver(tester);
    expect(find.text(l10n.matureStoryUnavailableLabel), findsOneWidget);
  });

  testWidgets('a list of only in-review and unavailable stories is not empty',
      (tester) async {
    await pump(
        tester,
        FakeStoryRepository(stories: [
          story('pending', reviewed: false),
          story('mature', authors: [_other, _other], mature: true),
        ]),
        birthYears: {_me: minorYear});

    expect(find.text(l10n.noIncompleteStories), findsNothing);
    expect(find.byType(ListTile), findsNWidgets(2));
  });

  group('mature stories hidden from minors (flag off)', () {
    testWidgets('a known minor does not see mature stories', (tester) async {
      await pump(
          tester,
          FakeStoryRepository(stories: [
            story('mature', mature: true),
            story('clean', authors: [_other]),
          ]),
          birthYears: {_me: minorYear},
          matureVisibleToMinors: false);

      expect(find.byKey(const ValueKey('mature')), findsNothing);
      expect(find.byKey(const ValueKey('clean')), findsOneWidget);
      expect(find.text(l10n.matureStoryUnavailableLabel), findsNothing);
    });

    testWidgets(
        'a known minor in a room of mature stories only sees the empty state',
        (tester) async {
      await pump(
          tester,
          FakeStoryRepository(stories: [
            story('mature', authors: [_other, _other], mature: true),
          ]),
          birthYears: {_me: minorYear},
          matureVisibleToMinors: false);

      expect(find.text(l10n.noIncompleteStories), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('while the stored-year read runs, a mature tile is locked',
        (tester) async {
      final read = Completer<int?>();
      await pump(
          tester, FakeStoryRepository(stories: [story('s', mature: true)]),
          birthYears: {_me: minorYear},
          read: read.future,
          matureVisibleToMinors: false);

      expect(find.text(l10n.matureStoryLockedTitle), findsOneWidget);
      expect(listTile(tester, 's').enabled, isTrue);

      read.complete(minorYear);
      await deliver(tester);
      expect(find.byKey(const ValueKey('s')), findsNothing);
      expect(find.text(l10n.noIncompleteStories), findsOneWidget);
    });

    testWidgets(
        'a minor verdict shows the snackbar once, then hides every mature '
        'tile', (tester) async {
      await pump(
          tester,
          FakeStoryRepository(stories: [
            story('a', mature: true),
            story('b', mature: true, authors: [_other, _other]),
            story('clean', authors: [_other]),
          ]),
          source: _Source.value(AgeSignal.minor),
          matureVisibleToMinors: false);

      await tester.tap(tileOf('a'));
      await tester.pumpAndSettle();

      expect(find.text(l10n.matureStoryUnavailable), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.byKey(const ValueKey('a')), findsNothing);
      expect(find.byKey(const ValueKey('b')), findsNothing);
      expect(find.byKey(const ValueKey('clean')), findsOneWidget);
      expect(gate.resolves, 1);
    });
  });

  testWidgets('every state has the same tile height', (tester) async {
    await pump(
        tester,
        FakeStoryRepository(stories: [
          story('available'),
          story('pending', authors: [_other, _other], reviewed: false),
          story('mature', authors: [_other, _other, _other], mature: true),
        ]));

    final heights =
        find.byType(ListTile).evaluate().map((e) => e.size!.height).toSet();
    expect(heights, hasLength(1));
  });

  testWidgets('the new story button creates a story and opens it',
      (tester) async {
    final stories = FakeStoryRepository();
    await pump(tester, stories, roomId: 'friends');

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(stories.stories.values.single.roomId, 'friends');
  });

  testWidgets(
      'the new story button explains why a user with a waiting '
      'introduction cannot start another', (tester) async {
    final stories = FakeStoryRepository(stories: [
      Story(
        id: 's1',
        status: 'incomplete',
        currentPosition: kStoryPositions[1],
        parts: [
          StoryPart(
            position: kStoryPositions.first,
            text: 'Once upon a time',
            author: 'me@example.com',
            timestamp: DateTime.utc(2026, 10, 1),
          ),
        ],
        language: 'it',
      ),
    ]);
    await pump(tester, stories);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text(l10n.newStoryBlocked), findsOneWidget);
    expect(find.byType(ChatScreen), findsNothing);
    expect(stories.stories, hasLength(1));
  });

  testWidgets('a failed creation shows an error', (tester) async {
    final stories = FakeStoryRepository()..failWith = Exception('offline');
    await pump(tester, stories);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text(l10n.genericError), findsOneWidget);
    expect(find.byType(ChatScreen), findsNothing);
  });
}
