import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/ads/ads_repository.dart';
import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/safety/safety_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/data/services/age_signals_source.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/models/app_config.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/complete_stories/widgets/age_check_screen.dart';
import 'package:cadavre_exquisite/ui/complete_stories/widgets/complete_stories_screen.dart';
import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/story_read/widgets/story_read_screen.dart';

import '../../../testing/fakes/repositories/fake_ads_repository.dart';
import '../../../testing/fakes/repositories/fake_age_check_repository.dart';
import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_safety_repository.dart';
import '../../../testing/fakes/repositories/fake_story_repository.dart';
import '../../../testing/fakes/repositories/fake_user_profile_repository.dart';

const _me = 'me@example.com';
const _field = ValueKey('storySearchField');
const _clear = ValueKey('storySearchClear');

class _Source implements AgeSignalsSource {
  _Source(this.signal);

  AgeSignal signal;

  @override
  Future<AgeSignal> check() async => signal;
}

/// An [AgeGate] whose quiet stored-birth-year read waits for [read].
class _DelayedReadGate extends AgeGate {
  _DelayedReadGate(this.read, {required super.signals, required super.storage});

  final Future<int?> read;

  @override
  Future<int?> storedBirthYear(String email) => read;
}

/// An [AgeGate] counting its [resolve] calls.
class _CountingGate extends AgeGate {
  _CountingGate({required super.signals, required super.storage, super.clock});

  int resolves = 0;

  @override
  Future<AgeVerdict> resolve(String email) {
    resolves++;
    return super.resolve(email);
  }
}

/// A [StoryRepository] whose completed stories never arrive.
class _SilentStoryRepository extends FakeStoryRepository {
  @override
  Stream<List<Story>> completeStoriesStream({
    required String language,
    String? roomId,
  }) =>
      StreamController<List<Story>>().stream;
}

final _now = DateTime.utc(2026, 10, 21);

/// A completed story; with [reviewed] false it still awaits its completion
/// review (no `reviewedAt`).
Story _story(
  String id, {
  String? title,
  List<String> keywords = const [],
  String author = 'someone@example.com',
  String? text,
  bool mature = false,
  String language = 'it',
  int minutesAgo = 0,
  bool reviewed = true,
}) =>
    Story(
      id: id,
      status: 'complete',
      currentPosition: 'epilogo',
      parts: [
        StoryPart(
          position: kStoryPositions.first,
          text: text ?? 'testo di $id',
          author: author,
          timestamp: _now.subtract(Duration(minutes: minutesAgo)),
        ),
      ],
      title: title,
      keywords: keywords,
      mature: mature,
      language: language,
      reviewedAt: reviewed ? _now : null,
    );

/// Newest first: others o-drago, o-faro, o-nonna; mine m-isola, m-scuola.
List<Story> _room() => [
      _story('o-drago',
          title: 'Il drago di ghiaccio',
          keywords: ['ghiaccio', 'montagna'],
          minutesAgo: 1),
      _story('m-isola',
          author: _me,
          text: "C'era un'isola",
          keywords: ['drago', 'isola', 'nonna'],
          minutesAgo: 2),
      _story('o-faro',
          title: 'Il faro', keywords: ['tempesta', 'mare'], minutesAgo: 3),
      _story('m-scuola', author: _me, title: 'La scuola', minutesAgo: 4),
      _story('o-nonna', title: 'La nonna e il gatto', minutesAgo: 5),
    ];

void main() {
  late AppLocalizations l10n;
  late _Source source;
  late FakeAgeCheckRepository ages;
  late AgeGate gate;

  setUp(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('it'));
    source = _Source(AgeSignal.unavailable);
    ages = FakeAgeCheckRepository();
    gate = AgeGate(signals: source, storage: ages, clock: () => _now);
  });

  Widget app(
    StoryRepository stories, {
    String language = 'it',
    String? roomId,
    Locale locale = const Locale('it'),
    bool matureVisibleToMinors = true,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthRepository>(
            create: (_) => FakeAuthRepository(email: _me)),
        ChangeNotifierProvider<AdsRepository>(
            create: (_) => FakeAdsRepository()),
        Provider<StoryRepository>.value(value: stories),
        Provider<AppConfig>.value(
            value: AppConfig(matureVisibleToMinors: matureVisibleToMinors)),
        Provider<AgeGate>.value(value: gate),
        ChangeNotifierProvider<SafetyRepository>(
            create: (_) => FakeSafetyRepository()),
        Provider<UserProfileRepository>(
            create: (_) => FakeUserProfileRepository()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: CompleteStoriesScreen(language: language, roomId: roomId),
      ),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    List<Story>? stories,
    Locale locale = const Locale('it'),
    bool matureVisibleToMinors = true,
  }) async {
    await tester.pumpWidget(app(
        FakeStoryRepository(stories: stories ?? _room()),
        locale: locale,
        matureVisibleToMinors: matureVisibleToMinors));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(_field), text);
    // No debounce: a single frame shows the result.
    await tester.pump();
  }

  bool fieldFocused(WidgetTester tester) => tester
      .widget<EditableText>(find.descendant(
          of: find.byKey(_field), matching: find.byType(EditableText)))
      .focusNode
      .hasFocus;

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(_field)).controller!.text;

  /// The titles of the tiles in the visible tab, top to bottom.
  List<String> visibleTitles(WidgetTester tester) {
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile));
    return [for (final tile in tiles) (tile.title! as Text).data!];
  }

  Finder tab(String label) =>
      find.descendant(of: find.byType(Tab), matching: find.text(label));

  Future<void> selectTab(WidgetTester tester, String label) async {
    await tester.tap(tab(label));
    await tester.pumpAndSettle();
  }

  int selectedTab(WidgetTester tester) =>
      tester.widget<TabBar>(find.byType(TabBar)).controller!.index;

  /// The keyword line of the tile showing [joined].
  RichText keywordLine(WidgetTester tester, String joined) =>
      tester.widget<RichText>(find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == joined));

  /// The style of the keyword [keyword] inside [line].
  TextStyle? keywordStyle(RichText line, String keyword) {
    TextStyle? found;
    line.text.visitChildren((span) {
      if (span is TextSpan && span.text == keyword) {
        found = span.style;
        return false;
      }
      return true;
    });
    return found;
  }

  group('field', () {
    testWidgets('sits above the tabs, with the Italian hint', (tester) async {
      await pumpScreen(tester);

      expect(find.byKey(_field), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);
      expect(tester.getBottomLeft(find.byKey(_field)).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.byType(TabBar)).dy));
      expect(find.text('Cerca per titolo o argomento'), findsOneWidget);
      final field = tester.widget<TextField>(find.byKey(_field));
      expect(field.textInputAction, TextInputAction.search);
      expect(field.autocorrect, isFalse);
      expect(field.autofocus, isFalse);
    });

    testWidgets('has the English hint', (tester) async {
      await pumpScreen(tester, locale: const Locale('en'));

      expect(find.text('Search by title or topic'), findsOneWidget);
    });

    testWidgets('is absent while loading', (tester) async {
      await tester.pumpWidget(app(_SilentStoryRepository()));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(_field), findsNothing);
      expect(find.byType(TabBar), findsNothing);
    });

    testWidgets('is absent when the room has no completed stories',
        (tester) async {
      await pumpScreen(tester, stories: []);

      expect(find.text(l10n.noCompleteStories), findsOneWidget);
      expect(find.byKey(_field), findsNothing);
      expect(find.byType(TabBar), findsNothing);
    });

    testWidgets('cuts pasted text at 50 characters', (tester) async {
      await pumpScreen(tester);

      await type(tester, 'a' * 80);

      expect(fieldText(tester), hasLength(50));
    });
  });

  group('filtering', () {
    testWidgets(
        'typing filters both tabs at once, by title and by keyword, '
        'newest first', (tester) async {
      await pumpScreen(tester);
      expect(visibleTitles(tester),
          ['Il drago di ghiaccio', 'Il faro', 'La nonna e il gatto']);

      await type(tester, 'drag');

      // By title.
      expect(visibleTitles(tester), ['Il drago di ghiaccio']);
      expect(tab('Altre storie (1)'), findsOneWidget);
      // By keyword, in the other tab, already counted on the same frame.
      expect(tab('Le tue storie (1)'), findsOneWidget);
      await selectTab(tester, 'Le tue storie (1)');
      expect(visibleTitles(tester), ["C'era un'isola"]);

      await type(tester, 'nonna');
      expect(visibleTitles(tester), ["C'era un'isola"]);
      await selectTab(tester, 'Altre storie (1)');
      expect(visibleTitles(tester), ['La nonna e il gatto']);
    });

    testWidgets(
        'tab labels show counts only while searching, and the tab never '
        'changes because of typing', (tester) async {
      await pumpScreen(tester);
      expect(tab(l10n.otherStoriesTab), findsOneWidget);
      expect(tab(l10n.yourStoriesHeading), findsOneWidget);
      expect(selectedTab(tester), 0);

      // Only the user's tab matches: still on the other one.
      await type(tester, 'scuola');
      expect(tab('Altre storie (0)'), findsOneWidget);
      expect(tab('Le tue storie (1)'), findsOneWidget);
      expect(selectedTab(tester), 0);

      await type(tester, '   ');
      expect(tab(l10n.otherStoriesTab), findsOneWidget);
      expect(tab(l10n.yourStoriesHeading), findsOneWidget);
      expect(visibleTitles(tester), hasLength(3));
      expect(selectedTab(tester), 0);
    });

    testWidgets('a whitespace query shows the clear button but filters nothing',
        (tester) async {
      await pumpScreen(tester);

      await type(tester, '  ');

      expect(find.byKey(_clear), findsOneWidget);
      expect(visibleTitles(tester), hasLength(3));
    });
  });

  group('clear button', () {
    testWidgets('appears with text, is 48x48 and restores the lists',
        (tester) async {
      await pumpScreen(tester);
      expect(find.byKey(_clear), findsNothing);

      await type(tester, 'faro');
      expect(find.byKey(_clear), findsOneWidget);
      expect(find.byTooltip('Cancella ricerca'), findsOneWidget);
      final size = tester.getSize(find.byKey(_clear));
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));
      expect(visibleTitles(tester), ['Il faro']);
      expect(fieldFocused(tester), isTrue);

      await tester.tap(find.byKey(_clear));
      await tester.pump();

      expect(fieldText(tester), isEmpty);
      expect(find.byKey(_clear), findsNothing);
      expect(visibleTitles(tester), hasLength(3));
      expect(tab(l10n.otherStoriesTab), findsOneWidget);
      // The keyboard stays open.
      expect(fieldFocused(tester), isTrue);
    });

    testWidgets('does not focus the field when the keyboard was closed',
        (tester) async {
      await pumpScreen(tester);
      await type(tester, 'faro');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(fieldFocused(tester), isFalse);

      await tester.tap(find.byKey(_clear));
      await tester.pump();

      expect(fieldText(tester), isEmpty);
      expect(fieldFocused(tester), isFalse);
    });
  });

  group('no matches', () {
    testWidgets(
        'no match here but some in the other tab offers to switch to it',
        (tester) async {
      await pumpScreen(tester);

      await type(tester, 'scuola');

      expect(find.text('Nessuna storia trovata qui per «scuola».'),
          findsOneWidget);
      final button =
          find.widgetWithText(TextButton, 'Vedi 1 storia in «Le tue storie»');
      expect(button, findsOneWidget);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48.0));

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(selectedTab(tester), 1);
      expect(visibleTitles(tester), ['La scuola']);
      // The search is unchanged.
      expect(fieldText(tester), 'scuola');
    });

    testWidgets('the switch button counts several matches', (tester) async {
      await pumpScreen(tester, stories: [
        ..._room(),
        _story('m-isola2', author: _me, keywords: ['isola'], minutesAgo: 9),
      ]);

      await type(tester, 'isola');

      expect(find.text('Vedi 2 storie in «Le tue storie»'), findsOneWidget);
    });

    testWidgets(
        'no match anywhere shows the query, the hint and a clear button '
        'in both tabs', (tester) async {
      await pumpScreen(tester);

      await type(tester, '  draghi   volanti ');

      const message = 'Nessuna storia trovata per «draghi volanti».';
      expect(find.text(message), findsOneWidget);
      expect(find.text(l10n.noMatchingStoriesHint), findsOneWidget);
      expect(
          find.text("Prova con un'altra parola, oppure scrivila al singolare."),
          findsOneWidget);
      await selectTab(tester, 'Le tue storie (0)');
      expect(find.text(message), findsOneWidget);

      final button = find.widgetWithText(TextButton, 'Cancella ricerca');
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(fieldText(tester), isEmpty);
      expect(visibleTitles(tester), ["C'era un'isola", 'La scuola']);
      expect(tab(l10n.yourStoriesHeading), findsOneWidget);
    });

    testWidgets('the message follows the typed text', (tester) async {
      await pumpScreen(tester);

      await type(tester, 'astronave');
      await type(tester, 'astronave x');

      // "x" is too short to change the filter, but the message quotes it.
      expect(find.text('Nessuna storia trovata per «astronave x».'),
          findsOneWidget);
    });

    testWidgets('a tab without stories keeps its own message while searching',
        (tester) async {
      await pumpScreen(tester, stories: [
        _story('o-drago', title: 'Il drago'),
      ]);
      await selectTab(tester, l10n.yourStoriesHeading);
      expect(find.text(l10n.noYourCompleteStories), findsOneWidget);

      await type(tester, 'drago');
      expect(find.text(l10n.noYourCompleteStories), findsOneWidget);
      expect(find.textContaining('Nessuna storia trovata'), findsNothing);

      await type(tester, 'astronave');
      expect(find.text(l10n.noYourCompleteStories), findsOneWidget);
      expect(find.textContaining('Nessuna storia trovata'), findsNothing);
    });
  });

  group('keywords on tiles', () {
    testWidgets('are listed joined by a dot, also when not searching',
        (tester) async {
      await pumpScreen(tester);

      expect(find.text('ghiaccio · montagna'), findsOneWidget);
      expect(find.text('tempesta · mare'), findsOneWidget);
      // "La nonna e il gatto" has no keywords: no line, no tag icon.
      expect(find.byIcon(Icons.tag), findsNWidgets(2));
      final nonna = find.ancestor(
          of: find.text('La nonna e il gatto'),
          matching: find.byType(ListTile));
      expect(find.descendant(of: nonna, matching: find.byIcon(Icons.tag)),
          findsNothing);

      // Not highlighted when not searching.
      final line = keywordLine(tester, 'ghiaccio · montagna');
      expect(
          keywordStyle(line, 'ghiaccio')?.fontWeight, isNot(FontWeight.w700));
    });

    testWidgets('the matching keyword is bold and dark green', (tester) async {
      await pumpScreen(tester);

      await type(tester, 'ghiac');

      final line = keywordLine(tester, 'ghiaccio · montagna');
      final match = keywordStyle(line, 'ghiaccio');
      expect(match?.fontWeight, FontWeight.w700);
      expect(match?.color, AppColors.primaryDark);
      final other = keywordStyle(line, 'montagna');
      expect(other?.fontWeight, isNot(FontWeight.w700));
      expect(other?.color, isNot(AppColors.primaryDark));
    });
  });

  group('mature stories', () {
    const matureText = 'testo esplicito del pirata';
    List<Story> withMature() => [
          _story('mature',
              mature: true,
              title: 'Il veliero',
              text: matureText,
              keywords: ['pirata', 'tesoro'],
              minutesAgo: 1),
          _story('normal', title: 'Il faro', minutesAgo: 2),
        ];

    testWidgets(
        'a locked tile found by keyword shows title, label and keywords, '
        'never the text, and runs the gate flow', (tester) async {
      await pumpScreen(tester, stories: withMature());

      await type(tester, 'pirata');

      expect(find.byIcon(Icons.lock), findsOneWidget);
      expect(find.text('Il veliero'), findsOneWidget);
      expect(
          find.text('${l10n.matureStoryLockedTitle} · ${l10n.authorsCount(1)}'),
          findsOneWidget);
      expect(find.text('pirata · tesoro'), findsOneWidget);
      expect(find.text(matureText), findsNothing);
      expect(find.textContaining(matureText), findsNothing);
      expect(find.textContaining('esplicito del'), findsNothing);

      // No signal: the birth-year screen, as without search.
      await tester.tap(find.text('Il veliero'));
      await tester.pumpAndSettle();
      expect(find.byType(AgeCheckScreen), findsOneWidget);
    });

    testWidgets(
        'after an adult verdict the matching tile unlocks in place, '
        'still filtered', (tester) async {
      source.signal = AgeSignal.adult;
      await pumpScreen(tester, stories: withMature());
      await type(tester, 'pirata');

      await tester.tap(find.text('Il veliero'));
      await tester.pumpAndSettle();
      expect(find.byType(StoryReadScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(StoryReadScreen))).pop();
      await tester.pumpAndSettle();

      expect(fieldText(tester), 'pirata');
      expect(visibleTitles(tester), ['Il veliero']);
      expect(find.byIcon(Icons.lock), findsNothing);
      expect(find.byIcon(Icons.lock_open), findsOneWidget);
    });

    testWidgets(
        'a known minor finds a mature story by keyword as an unavailable '
        'tile, bold match and tab count included, and never runs the gate',
        (tester) async {
      ages = FakeAgeCheckRepository(birthYears: {_me: 2015});
      final counting =
          _CountingGate(signals: source, storage: ages, clock: () => _now);
      gate = counting;
      await pumpScreen(tester, stories: withMature());

      await type(tester, 'pirata');

      expect(visibleTitles(tester), ['Il veliero']);
      expect(tab('Altre storie (1)'), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsOneWidget);
      expect(
          find.text(
              '${l10n.matureStoryUnavailableLabel} · ${l10n.authorsCount(1)}'),
          findsOneWidget);
      expect(find.textContaining(matureText), findsNothing);
      final line = keywordLine(tester, 'pirata · tesoro');
      expect(keywordStyle(line, 'pirata')!.fontWeight, FontWeight.w700);
      expect(tester.widget<ListTile>(find.byType(ListTile)).enabled, isFalse);

      await tester.tap(find.text('Il veliero'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(AgeCheckScreen), findsNothing);
      expect(find.byType(StoryReadScreen), findsNothing);
      expect(counting.resolves, 0);
    });

    testWidgets(
        'a known minor in a room with only mature stories sees them, not the '
        'empty state', (tester) async {
      ages = FakeAgeCheckRepository(birthYears: {_me: 2015});
      gate = AgeGate(signals: source, storage: ages, clock: () => _now);
      await pumpScreen(tester, stories: [withMature().first]);

      expect(find.text(l10n.noCompleteStories), findsNothing);
      expect(find.byKey(_field), findsOneWidget);
      expect(find.text('Il veliero'), findsOneWidget);
      expect(
          find.text(
              '${l10n.matureStoryUnavailableLabel} · ${l10n.authorsCount(1)}'),
          findsOneWidget);
    });

    testWidgets(
        'while the birth year loads, a mature story matches as locked, then '
        'turns unavailable for a stored minor', (tester) async {
      final read = Completer<int?>();
      gate = _DelayedReadGate(read.future, signals: source, storage: ages);
      await tester.pumpWidget(app(FakeStoryRepository(stories: withMature())));
      await tester.pump();

      await type(tester, 'pirata');

      expect(visibleTitles(tester), ['Il veliero']);
      expect(
          find.text('${l10n.matureStoryLockedTitle} · ${l10n.authorsCount(1)}'),
          findsOneWidget);

      read.complete(2015);
      await tester.pumpAndSettle();
      expect(visibleTitles(tester), ['Il veliero']);
      expect(
          find.text(
              '${l10n.matureStoryUnavailableLabel} · ${l10n.authorsCount(1)}'),
          findsOneWidget);
    });

    testWidgets(
        'a minor verdict keeps the only story listed as unavailable, and the '
        'search', (tester) async {
      source.signal = AgeSignal.minor;
      final repository = FakeStoryRepository(stories: [withMature().first]);
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      await type(tester, 'pirata');

      await tester.tap(find.text('Il veliero'));
      await tester.pumpAndSettle();

      expect(find.text(l10n.matureStoryUnavailable), findsOneWidget);
      expect(find.text(l10n.noCompleteStories), findsNothing);
      expect(fieldText(tester), 'pirata');
      expect(visibleTitles(tester), ['Il veliero']);
      expect(tester.widget<ListTile>(find.byType(ListTile)).enabled, isFalse);
    });

    testWidgets(
        'a story awaiting its completion review is never listed, matched or '
        'counted, even flagged mature', (tester) async {
      await pumpScreen(tester, stories: [
        _story('pending',
            mature: true,
            reviewed: false,
            title: 'Il veliero nascosto',
            keywords: ['segreto'],
            minutesAgo: 1),
        _story('normal', title: 'Il faro', minutesAgo: 2),
      ]);

      expect(visibleTitles(tester), ['Il faro']);
      await type(tester, 'segreto');
      expect(find.text('Il veliero nascosto'), findsNothing);
      expect(tab('Altre storie (0)'), findsOneWidget);
      await type(tester, 'veliero');
      expect(find.text('Il veliero nascosto'), findsNothing);

      // Alone in the room, it leaves the room empty.
      await tester.pumpWidget(const SizedBox());
      await pumpScreen(tester, stories: [
        _story('pending', mature: true, reviewed: false, title: 'Nascosto'),
      ]);
      expect(find.text(l10n.noCompleteStories), findsOneWidget);
    });
  });

  group('mature stories hidden from minors (flag off)', () {
    List<Story> withMature() => [
          _story('mature',
              mature: true,
              title: 'Il veliero',
              keywords: ['pirata', 'tesoro'],
              minutesAgo: 1),
          _story('normal', title: 'Il faro', minutesAgo: 2),
        ];

    testWidgets(
        'a known minor neither sees nor finds a mature story, and it is not '
        'counted', (tester) async {
      ages = FakeAgeCheckRepository(birthYears: {_me: 2015});
      gate = AgeGate(signals: source, storage: ages, clock: () => _now);
      await pumpScreen(tester,
          stories: withMature(), matureVisibleToMinors: false);

      expect(visibleTitles(tester), ['Il faro']);
      expect(find.byIcon(Icons.lock), findsNothing);

      await type(tester, 'pirata');
      expect(find.text('Il veliero'), findsNothing);
      expect(tab('Altre storie (0)'), findsOneWidget);
      expect(find.text(l10n.noMatchingStories('pirata')), findsOneWidget);
    });

    testWidgets(
        'a known minor in a room with only mature stories gets the empty '
        'state, without the search field', (tester) async {
      ages = FakeAgeCheckRepository(birthYears: {_me: 2015});
      gate = AgeGate(signals: source, storage: ages, clock: () => _now);
      await pumpScreen(tester,
          stories: [withMature().first], matureVisibleToMinors: false);

      expect(find.text(l10n.noCompleteStories), findsOneWidget);
      expect(find.byKey(_field), findsNothing);
      expect(find.text('Il veliero'), findsNothing);
    });

    testWidgets(
        'while the birth year loads, a mature story matches as locked, then '
        'disappears for a stored minor', (tester) async {
      final read = Completer<int?>();
      gate = _DelayedReadGate(read.future, signals: source, storage: ages);
      await tester.pumpWidget(app(FakeStoryRepository(stories: withMature()),
          matureVisibleToMinors: false));
      await tester.pump();

      await type(tester, 'pirata');
      expect(visibleTitles(tester), ['Il veliero']);
      expect(
          find.text('${l10n.matureStoryLockedTitle} · ${l10n.authorsCount(1)}'),
          findsOneWidget);

      read.complete(2015);
      await tester.pumpAndSettle();
      expect(find.text('Il veliero'), findsNothing);
      expect(tab('Altre storie (0)'), findsOneWidget);
    });

    testWidgets(
        'a minor verdict shows the snackbar once, then hides the mature '
        'tiles', (tester) async {
      source.signal = AgeSignal.minor;
      await pumpScreen(tester,
          stories: withMature(), matureVisibleToMinors: false);

      await tester.tap(find.text('Il veliero'));
      await tester.pumpAndSettle();

      expect(find.text(l10n.matureStoryUnavailable), findsOneWidget);
      expect(find.byType(StoryReadScreen), findsNothing);
      expect(visibleTitles(tester), ['Il faro']);
      expect(find.byIcon(Icons.lock), findsNothing);
    });

    testWidgets(
        'a minor verdict on the only story empties the room and drops the '
        'search', (tester) async {
      source.signal = AgeSignal.minor;
      await pumpScreen(tester,
          stories: [withMature().first], matureVisibleToMinors: false);
      await type(tester, 'pirata');

      await tester.tap(find.text('Il veliero'));
      await tester.pumpAndSettle();

      expect(find.text(l10n.matureStoryUnavailable), findsOneWidget);
      expect(find.text(l10n.noCompleteStories), findsOneWidget);
      expect(find.byKey(_field), findsNothing);
    });
  });

  group('keyboard', () {
    testWidgets('submitting unfocuses and keeps the results', (tester) async {
      await pumpScreen(tester);
      await type(tester, 'faro');
      expect(fieldFocused(tester), isTrue);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(fieldFocused(tester), isFalse);
      expect(fieldText(tester), 'faro');
      expect(visibleTitles(tester), ['Il faro']);
    });

    testWidgets('dragging a list closes the keyboard', (tester) async {
      await pumpScreen(tester, stories: [
        for (var i = 0; i < 20; i++)
          _story('s$i', title: 'Storia $i', minutesAgo: i),
      ]);
      await type(tester, 'storia');
      expect(fieldFocused(tester), isTrue);

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(fieldFocused(tester), isFalse);
    });

    testWidgets('typing scrolls the results back to the top', (tester) async {
      await pumpScreen(tester, stories: [
        for (var i = 0; i < 20; i++)
          _story('s$i', title: 'Storia $i', minutesAgo: i),
      ]);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.controller!.offset, greaterThan(0));

      await type(tester, 'stor');

      expect(list.controller!.offset, 0);
    });

    testWidgets(
        'switching tab keeps the keyboard; tapping a tile closes it before '
        'opening the story', (tester) async {
      await pumpScreen(tester);
      await type(tester, 'drag');

      await selectTab(tester, 'Le tue storie (1)');
      expect(fieldFocused(tester), isTrue);

      await tester.tap(find.text("C'era un'isola"));
      await tester.pumpAndSettle();
      expect(find.byType(StoryReadScreen), findsOneWidget);

      Navigator.of(tester.element(find.byType(StoryReadScreen))).pop();
      await tester.pumpAndSettle();
      // Focus didn't return to the field.
      expect(fieldFocused(tester), isFalse);
      expect(fieldText(tester), 'drag');
    });
  });

  group('room change', () {
    testWidgets('a different room empties the field and lists it unfiltered',
        (tester) async {
      final repository = FakeStoryRepository(stories: [
        ..._room(),
        _story('en-1', title: 'The lighthouse', language: 'en'),
        _story('en-2', title: 'The dragon', language: 'en'),
      ]);
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      await type(tester, 'faro');
      expect(visibleTitles(tester), ['Il faro']);

      await tester.pumpWidget(app(repository, language: 'en'));
      await tester.pumpAndSettle();

      expect(fieldText(tester), isEmpty);
      expect(tab(l10n.otherStoriesTab), findsOneWidget);
      // Same completion time: ordered by id.
      expect(visibleTitles(tester), ['The lighthouse', 'The dragon']);
    });

    testWidgets('the same room keeps the search', (tester) async {
      final repository = FakeStoryRepository(stories: _room());
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      await type(tester, 'faro');

      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();

      expect(fieldText(tester), 'faro');
      expect(visibleTitles(tester), ['Il faro']);
    });
  });

  group('semantics', () {
    testWidgets('the field is named with and without text', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester);

      SemanticsData field() =>
          tester.getSemantics(find.byType(EditableText)).getSemanticsData();

      expect(field().label, contains('Cerca storie'));
      expect(field().flagsCollection.isTextField, isTrue);

      await type(tester, 'faro');
      expect(field().label, contains('Cerca storie'));
      expect(field().value, 'faro');
      // Named once, not twice.
      expect('Cerca storie'.allMatches(field().label), hasLength(1));
      handle.dispose();
    });

    testWidgets('the keyword line reads as topics', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester);

      expect(find.bySemanticsLabel(RegExp('Argomenti: ghiaccio, montagna')),
          findsOneWidget);
      handle.dispose();
    });

    testWidgets('the no-match message is a live region', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester);

      await type(tester, 'astronave');

      final message = find.text('Nessuna storia trovata per «astronave».');
      expect(
        find.ancestor(
          of: message,
          matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.liveRegion == true),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
