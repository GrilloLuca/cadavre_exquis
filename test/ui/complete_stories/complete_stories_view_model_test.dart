import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/data/services/age_signals_source.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/ui/complete_stories/view_models/complete_stories_view_model.dart';
import 'package:cadavre_exquisite/ui/core/view_models/mature_story_access.dart';

import '../../../testing/fakes/repositories/fake_age_check_repository.dart';
import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_story_repository.dart';

const _me = 'me@example.com';

class _Source implements AgeSignalsSource {
  _Source(this.signal);

  AgeSignal signal;

  @override
  Future<AgeSignal> check() async => signal;
}

void main() {
  final now = DateTime.utc(2026, 10, 12);

  Story story(
    String id, {
    bool? mature = false,
    String author = 'x@y.it',
    String? title,
    List<String> keywords = const [],
    String language = 'en',
    int minutesAgo = 0,
    bool reviewed = true,
  }) =>
      Story(
        id: id,
        status: 'complete',
        currentPosition: 'epilogo',
        parts: [
          StoryPart(
              position: 'introduzione',
              text: id,
              author: author,
              timestamp: now.subtract(Duration(minutes: minutesAgo))),
        ],
        mature: mature,
        language: language,
        title: title,
        keywords: keywords,
        reviewedAt: reviewed ? now : null,
      );

  late _Source source;
  late FakeAgeCheckRepository ages;
  late AgeGate gate;

  setUp(() {
    source = _Source(AgeSignal.adult);
    ages = FakeAgeCheckRepository();
    gate = AgeGate(signals: source, storage: ages, clock: () => now);
  });

  Future<CompleteStoriesViewModel> create(
    List<Story> stories, {
    bool matureVisibleToMinors = true,
  }) async {
    final viewModel = CompleteStoriesViewModel(
      storyRepository: FakeStoryRepository(stories: stories),
      authRepository: FakeAuthRepository(email: _me),
      ageGate: gate,
      language: 'en',
      now: () => now,
      matureVisibleToMinors: matureVisibleToMinors,
    );
    await pumpEventQueue();
    return viewModel;
  }

  List<String> ids(List<Story> stories) => [for (final s in stories) s.id];

  group('search', () {
    // Newest completed first: o1, m1, o2, m2, o3.
    List<Story> stories() => [
          story('o1', title: 'Il drago di ghiaccio', minutesAgo: 1),
          story('m1', author: _me, keywords: ['drago', 'isola'], minutesAgo: 2),
          story('o2', title: 'Il faro', keywords: ['tempesta'], minutesAgo: 3),
          story('m2', author: _me, title: 'Draghi a scuola', minutesAgo: 4),
          story('o3', keywords: ['nonna', 'castello'], minutesAgo: 5),
        ];

    test('starts unfiltered', () async {
      final viewModel = await create(stories());

      expect(viewModel.query, '');
      expect(viewModel.isSearching, isFalse);
      expect(ids(viewModel.sections.others), ['o1', 'o2', 'o3']);
      expect(ids(viewModel.sections.mine), ['m1', 'm2']);
    });

    test('filters both sections, by title and keyword, keeping the order',
        () async {
      final viewModel = await create(stories());

      viewModel.setQuery('drag');

      expect(viewModel.query, 'drag');
      expect(viewModel.isSearching, isTrue);
      expect(ids(viewModel.sections.others), ['o1']);
      expect(ids(viewModel.sections.mine), ['m1', 'm2']);
    });

    test('clearing the query restores the full lists', () async {
      final viewModel = await create(stories());
      viewModel.setQuery('faro');
      expect(ids(viewModel.sections.others), ['o2']);
      expect(viewModel.sections.mine, isEmpty);

      viewModel.setQuery('');

      expect(viewModel.isSearching, isFalse);
      expect(ids(viewModel.sections.others), ['o1', 'o2', 'o3']);
      expect(ids(viewModel.sections.mine), ['m1', 'm2']);
    });

    test('a whitespace-only query does not filter', () async {
      final viewModel = await create(stories());

      viewModel.setQuery('   ');

      expect(viewModel.isSearching, isFalse);
      expect(viewModel.sections.others, hasLength(3));
    });

    test('notifies only when the effective query changes', () async {
      final viewModel = await create(stories());
      var notified = 0;
      viewModel.addListener(() => notified++);

      viewModel.setQuery('drago');
      expect(notified, 1);
      viewModel.setQuery('drago ');
      viewModel.setQuery('Drago');
      viewModel.setQuery('il drago');
      expect(notified, 1);
      // The raw text still follows what was typed.
      expect(viewModel.query, 'il drago');
      viewModel.setQuery('drago isola');
      expect(notified, 2);
      viewModel.setQuery('   ');
      expect(notified, 3);
      viewModel.setQuery('');
      expect(notified, 3);
    });

    test('totalCounts ignore the query', () async {
      final viewModel = await create(stories());

      viewModel.setQuery('astronave');

      expect(viewModel.sections.mine, isEmpty);
      expect(viewModel.sections.others, isEmpty);
      expect(viewModel.totalCounts, (mine: 2, others: 3));
    });

    test('highlights the keywords matching the query', () async {
      final viewModel = await create(stories());
      expect(viewModel.highlights('drago'), isFalse);

      viewModel.setQuery('drag');

      expect(viewModel.highlights('drago'), isTrue);
      expect(viewModel.highlights('isola'), isFalse);
    });

    test('setRoom to a different room clears the query', () async {
      final viewModel = CompleteStoriesViewModel(
        storyRepository: FakeStoryRepository(stories: [
          ...stories(),
          story('it1', title: 'Il drago', language: 'it'),
          story('it2', title: 'La luna', language: 'it'),
        ]),
        authRepository: FakeAuthRepository(email: _me),
        ageGate: gate,
        language: 'en',
        now: () => now,
      );
      await pumpEventQueue();
      viewModel.setQuery('drago');

      viewModel.setRoom(language: 'it');
      await pumpEventQueue();

      expect(viewModel.query, '');
      expect(viewModel.isSearching, isFalse);
      expect(ids(viewModel.sections.others), ['it1', 'it2']);
    });

    test('setRoom to the same room keeps the query', () async {
      final viewModel = await create(stories());
      viewModel.setQuery('faro');
      var notified = 0;
      viewModel.addListener(() => notified++);

      viewModel.setRoom(language: 'en');

      expect(notified, 0);
      expect(viewModel.query, 'faro');
      expect(ids(viewModel.sections.others), ['o2']);
    });

    group('mature stories', () {
      List<Story> withMature() => [
            story('mature', mature: true, keywords: ['pirata']),
            story('normal', title: 'Il faro'),
          ];

      test(
          'a known minor gets a matching mature story too, unavailable, and '
          'it is counted', () async {
        ages = FakeAgeCheckRepository(birthYears: {_me: 2015});
        gate = AgeGate(signals: source, storage: ages, clock: () => now);
        final viewModel = await create(withMature());

        viewModel.setQuery('pirata');

        expect(viewModel.sections.mine, isEmpty);
        expect(ids(viewModel.sections.others), ['mature']);
        expect(viewModel.matureStateOf(viewModel.sections.others.single),
            MatureTileState.unavailable);
        expect(viewModel.totalCounts, (mine: 0, others: 2));
      });

      test('a session minor gets a matching mature story too, unavailable',
          () async {
        source.signal = AgeSignal.minor;
        final mature = withMature().first;
        final viewModel = await create(withMature());
        await viewModel.unlock.execute(mature);

        viewModel.setQuery('pirata');

        expect(ids(viewModel.sections.others), ['mature']);
        expect(viewModel.matureStateOf(mature), MatureTileState.unavailable);
        expect(viewModel.totalCounts, (mine: 0, others: 2));
      });

      test('while the birth year loads, mature stories match, locked',
          () async {
        final read = Completer<int?>();
        gate = _DelayedReadGate(read.future, storage: ages);
        final viewModel = await create(withMature());

        viewModel.setQuery('pirata');

        expect(ids(viewModel.sections.others), ['mature']);
        expect(viewModel.isLocked(viewModel.sections.others.single), isTrue);
        expect(viewModel.totalCounts, (mine: 0, others: 2));

        // A stored minor year turns it unavailable once read.
        read.complete(2015);
        await pumpEventQueue();
        expect(ids(viewModel.sections.others), ['mature']);
        expect(viewModel.matureStateOf(viewModel.sections.others.single),
            MatureTileState.unavailable);
      });

      test('unknown age: the matching mature story is listed, still locked',
          () async {
        final viewModel = await create(withMature());

        viewModel.setQuery('pirata');

        expect(ids(viewModel.sections.others), ['mature']);
        expect(viewModel.isLocked(viewModel.sections.others.single), isTrue);
        expect(viewModel.totalCounts, (mine: 0, others: 2));
      });
    });
  });

  group('mature stories hidden from minors (flag off)', () {
    List<Story> withMature() => [
          story('mature', mature: true, keywords: ['pirata']),
          story('mineMature', mature: true, author: _me, title: 'Pirati'),
          story('normal', title: 'Il faro'),
        ];

    test('a known minor: not listed, matched or counted', () async {
      ages = FakeAgeCheckRepository(birthYears: {_me: 2015});
      gate = AgeGate(signals: source, storage: ages, clock: () => now);
      final viewModel =
          await create(withMature(), matureVisibleToMinors: false);

      expect(viewModel.sections.mine, isEmpty);
      expect(ids(viewModel.sections.others), ['normal']);
      expect(viewModel.totalCounts, (mine: 0, others: 1));

      viewModel.setQuery('pirat');
      expect(viewModel.sections.mine, isEmpty);
      expect(viewModel.sections.others, isEmpty);
      expect(viewModel.totalCounts, (mine: 0, others: 1));
    });

    test('a known minor whose room has only mature stories gets no stories',
        () async {
      ages = FakeAgeCheckRepository(birthYears: {_me: 2015});
      gate = AgeGate(signals: source, storage: ages, clock: () => now);
      final viewModel = await create([withMature().first],
          matureVisibleToMinors: false);

      expect(viewModel.isLoaded, isTrue);
      expect(viewModel.totalCounts, (mine: 0, others: 0));
    });

    test('while the birth year loads, mature stories are listed, locked',
        () async {
      final read = Completer<int?>();
      gate = _DelayedReadGate(read.future, storage: ages);
      final viewModel =
          await create(withMature(), matureVisibleToMinors: false);

      expect(ids(viewModel.sections.others), ['mature', 'normal']);
      expect(viewModel.isLocked(viewModel.sections.others.first), isTrue);
      expect(viewModel.totalCounts, (mine: 1, others: 2));

      read.complete(2015);
      await pumpEventQueue();
      expect(ids(viewModel.sections.others), ['normal']);
      expect(viewModel.totalCounts, (mine: 0, others: 1));
    });

    test('a minor signal answers minor, then hides every mature story',
        () async {
      source.signal = AgeSignal.minor;
      final mature = withMature().first;
      final viewModel =
          await create(withMature(), matureVisibleToMinors: false);
      expect(viewModel.isLocked(mature), isTrue);

      await viewModel.unlock.execute(mature);

      expect(viewModel.unlock.value!.outcome, UnlockOutcome.minor);
      expect(ids(viewModel.sections.others), ['normal']);
      expect(viewModel.sections.mine, isEmpty);
      expect(viewModel.matureStateOf(mature), MatureTileState.hidden);
    });

    test('unknown age: mature stories are listed and locked', () async {
      final viewModel =
          await create(withMature(), matureVisibleToMinors: false);

      viewModel.setQuery('pirata');
      expect(ids(viewModel.sections.others), ['mature']);
      expect(viewModel.isLocked(viewModel.sections.others.single), isTrue);
    });
  });

  test(
      'stories awaiting their completion review are never listed, matched '
      'or counted, even flagged mature', () async {
    final viewModel = await create([
      story('pending', mature: true, reviewed: false, title: 'Il veliero'),
      story('legacy', reviewed: false, title: 'Il vecchio veliero'),
      story('normal', title: 'Il faro'),
    ]);

    expect(ids(viewModel.sections.others), ['normal']);
    expect(viewModel.totalCounts, (mine: 0, others: 1));
    viewModel.setQuery('veliero');
    expect(viewModel.sections.others, isEmpty);
  });

  test('lists my stories first, mature ones locked', () async {
    final viewModel = await create([
      story('other'),
      story('mature', mature: true),
      story('mine', author: _me),
    ]);

    final (:mine, :others) = viewModel.sections;
    expect(mine.map((s) => s.id), ['mine']);
    // Same completion time: the repository orders them by id.
    expect(others.map((s) => s.id), ['mature', 'other']);
    expect(viewModel.isLocked(others.first), isTrue);
    expect(viewModel.isLocked(others.last), isFalse);
  });

  test('an adult signal opens the story and unlocks the session', () async {
    final mature = story('mature', mature: true);
    final viewModel = await create([mature]);

    await viewModel.unlock.execute(mature);

    expect(viewModel.unlock.value!.outcome, UnlockOutcome.open);
    expect(viewModel.isLocked(mature), isFalse);
    expect(viewModel.checkingStoryId, isNull);
  });

  test('a minor signal keeps mature stories listed, unavailable', () async {
    source.signal = AgeSignal.minor;
    final mature = story('mature', mature: true);
    final viewModel = await create([mature, story('normal')]);

    await viewModel.unlock.execute(mature);

    expect(viewModel.unlock.value!.outcome, UnlockOutcome.minor);
    expect(viewModel.sections.others.map((s) => s.id), ['mature', 'normal']);
    expect(viewModel.matureStateOf(mature), MatureTileState.unavailable);
  });

  test('no signal asks the birth year, keeping the check running', () async {
    source.signal = AgeSignal.unavailable;
    final mature = story('mature', mature: true);
    final viewModel = await create([mature]);

    await viewModel.unlock.execute(mature);
    expect(viewModel.unlock.value!.outcome, UnlockOutcome.askBirthYear);
    expect(viewModel.checkingStoryId, 'mature');

    await viewModel.submitBirthYear.execute(1990);

    expect(viewModel.submitBirthYear.value!.outcome, UnlockOutcome.open);
    expect(viewModel.submitBirthYear.value!.story.id, 'mature');
    expect(await ages.getBirthYear(_me), 1990);
    expect(viewModel.checkingStoryId, isNull);
    expect(viewModel.isUnlocked, isTrue);
  });

  test('a minor birth year keeps the story unavailable', () async {
    source.signal = AgeSignal.unavailable;
    final mature = story('mature', mature: true);
    final viewModel = await create([mature]);

    await viewModel.unlock.execute(mature);
    await viewModel.submitBirthYear.execute(2015);

    expect(viewModel.submitBirthYear.value!.outcome, UnlockOutcome.minor);
    expect(ids(viewModel.sections.others), ['mature']);
    expect(viewModel.matureStateOf(mature), MatureTileState.unavailable);
  });

  test('cancelling the birth year changes nothing', () async {
    source.signal = AgeSignal.unavailable;
    final mature = story('mature', mature: true);
    final viewModel = await create([mature]);

    await viewModel.unlock.execute(mature);
    viewModel.cancelBirthYear();

    expect(viewModel.checkingStoryId, isNull);
    expect(viewModel.isLocked(mature), isTrue);
    expect(await ages.getBirthYear(_me), isNull);
  });

  test(
      'a stored minor sees mature stories unavailable, and unlock answers '
      'minor without the gate', () async {
    ages = FakeAgeCheckRepository(birthYears: {_me: 2015});
    final counting = _CountingGate(storage: ages, signals: source);
    gate = counting;
    final mature = story('mature', mature: true);
    final viewModel = await create([mature]);

    expect(ids(viewModel.sections.others), ['mature']);
    expect(viewModel.matureStateOf(mature), MatureTileState.unavailable);
    expect(viewModel.totalCounts, (mine: 0, others: 1));

    await viewModel.unlock.execute(mature);

    expect(viewModel.unlock.value!.outcome, UnlockOutcome.minor);
    expect(counting.resolves, 0);
    expect(viewModel.checkingStoryId, isNull);
  });

  test('a failing check reports the error and stops checking', () async {
    final mature = story('mature', mature: true);
    final viewModel = await create([mature]);
    gate = _FailingGate(storage: ages);
    final failing = CompleteStoriesViewModel(
      storyRepository: FakeStoryRepository(stories: [mature]),
      authRepository: FakeAuthRepository(email: _me),
      ageGate: gate,
      language: 'en',
    );
    await pumpEventQueue();

    await failing.unlock.execute(mature);

    expect(failing.unlock.error, isA<StateError>());
    expect(failing.checkingStoryId, isNull);
    expect(viewModel.isLocked(mature), isTrue);
  });
}

/// An [AgeGate] whose quiet stored-birth-year read waits for [read].
class _DelayedReadGate extends AgeGate {
  _DelayedReadGate(this.read, {required super.storage});

  final Future<int?> read;

  @override
  Future<int?> storedBirthYear(String email) => read;
}

/// An [AgeGate] counting its [resolve] calls.
class _CountingGate extends AgeGate {
  _CountingGate({required super.storage, super.signals});

  int resolves = 0;

  @override
  Future<AgeVerdict> resolve(String email) {
    resolves++;
    return super.resolve(email);
  }
}

class _FailingGate extends AgeGate {
  _FailingGate({required super.storage});

  @override
  Future<AgeVerdict> resolve(String email) async => throw StateError('down');
}
