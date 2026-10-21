import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/data/services/age_signals_source.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/ui/complete_stories/view_models/complete_stories_view_model.dart';

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
      );

  late _Source source;
  late FakeAgeCheckRepository ages;
  late AgeGate gate;

  setUp(() {
    source = _Source(AgeSignal.adult);
    ages = FakeAgeCheckRepository();
    gate = AgeGate(signals: source, storage: ages, clock: () => now);
  });

  Future<CompleteStoriesViewModel> create(List<Story> stories) async {
    final viewModel = CompleteStoriesViewModel(
      storyRepository: FakeStoryRepository(stories: stories),
      authRepository: FakeAuthRepository(email: _me),
      ageGate: gate,
      language: 'en',
      now: () => now,
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

      test('a known minor never gets a mature story from a query', () async {
        ages = FakeAgeCheckRepository(birthYears: {_me: 2015});
        gate = AgeGate(signals: source, storage: ages, clock: () => now);
        final viewModel = await create(withMature());

        viewModel.setQuery('pirata');

        expect(viewModel.sections.mine, isEmpty);
        expect(viewModel.sections.others, isEmpty);
        expect(viewModel.totalCounts, (mine: 0, others: 1));
      });

      test('a session minor never gets a mature story from a query', () async {
        source.signal = AgeSignal.minor;
        final mature = withMature().first;
        final viewModel = await create(withMature());
        await viewModel.unlock.execute(mature);

        viewModel.setQuery('pirata');

        expect(viewModel.sections.others, isEmpty);
        expect(viewModel.totalCounts, (mine: 0, others: 1));
      });

      test('while the birth year loads, mature stories do not match', () async {
        final read = Completer<int?>();
        gate = _DelayedReadGate(read.future, storage: ages);
        final viewModel = await create(withMature());

        viewModel.setQuery('pirata');

        expect(viewModel.sections.others, isEmpty);
        expect(viewModel.totalCounts, (mine: 0, others: 1));

        // Once the read finds no minor the locked tile can match.
        read.complete(null);
        await pumpEventQueue();
        expect(ids(viewModel.sections.others), ['mature']);
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

  test('a minor signal hides mature stories', () async {
    source.signal = AgeSignal.minor;
    final mature = story('mature', mature: true);
    final viewModel = await create([mature, story('normal')]);

    await viewModel.unlock.execute(mature);

    expect(viewModel.unlock.value!.outcome, UnlockOutcome.minor);
    expect(viewModel.sections.others.map((s) => s.id), ['normal']);
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
    expect(viewModel.sections.others, isEmpty);
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

  test('a stored minor never sees mature stories', () async {
    ages = FakeAgeCheckRepository(birthYears: {_me: 2015});
    gate = AgeGate(signals: source, storage: ages, clock: () => now);
    final viewModel = await create([story('mature', mature: true)]);

    expect(viewModel.sections.others, isEmpty);
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

class _FailingGate extends AgeGate {
  _FailingGate({required super.storage});

  @override
  Future<AgeVerdict> resolve(String email) async => throw StateError('down');
}
