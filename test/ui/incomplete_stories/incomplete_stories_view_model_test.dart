import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/data/services/age_signals_source.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/ui/core/view_models/mature_story_access.dart';
import 'package:cadavre_exquisite/ui/incomplete_stories/view_models/incomplete_stories_view_model.dart';

import '../../../testing/fakes/repositories/fake_age_check_repository.dart';
import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_story_repository.dart';

const _me = 'me@example.com';
const _other = 'other@example.com';

class _Source implements AgeSignalsSource {
  _Source(this.signal);

  AgeSignal signal;

  @override
  Future<AgeSignal> check() async => signal;
}

/// An [AgeGate] counting its [resolve] calls, whose quiet stored-year read
/// waits for [read] when given.
class _CountingGate extends AgeGate {
  _CountingGate({required super.signals, required super.storage, super.clock});

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
  final now = DateTime.utc(2026, 10, 12, 10);

  StoryPart part(int index, String author) => StoryPart(
      position: kStoryPositions[index],
      text: 'x',
      author: author,
      timestamp: now);

  /// An incomplete story whose parts were written by [authors]; with
  /// [reviewed] false its last part has no verdict yet.
  Story story(
    String id, {
    List<String> authors = const [],
    String? lockedBy,
    DateTime? lockedAt,
    String language = 'it',
    String? roomId,
    bool reviewed = true,
    bool? mature,
  }) =>
      Story(
        id: id,
        status: 'incomplete',
        currentPosition: kStoryPositions[authors.length],
        parts: [for (final (i, author) in authors.indexed) part(i, author)],
        lockedBy: lockedBy,
        lockedAt: lockedAt,
        language: language,
        roomId: roomId,
        mature: mature,
        partReviews: {
          for (var i = 0; i < authors.length; i++)
            if (reviewed || i < authors.length - 1)
              kStoryPositions[i]: PartVerdict.safe,
        },
      );

  /// [s] once its last part has a verdict, as the server writes it.
  Story reviewed(Story s, {PartVerdict verdict = PartVerdict.safe}) => Story(
        id: s.id,
        status: s.status,
        currentPosition: s.currentPosition,
        parts: s.parts,
        lockedBy: s.lockedBy,
        lockedAt: s.lockedAt,
        language: s.language,
        roomId: s.roomId,
        mature: verdict == PartVerdict.mature ? true : s.mature,
        partReviews: {...s.partReviews, s.parts.last.position: verdict},
      );

  late FakeStoryRepository stories;
  late _Source source;
  late FakeAgeCheckRepository ages;
  late _CountingGate gate;

  setUp(() {
    source = _Source(AgeSignal.adult);
    ages = FakeAgeCheckRepository();
    gate = _CountingGate(signals: source, storage: ages, clock: () => now);
  });

  IncompleteStoriesViewModel create({
    String language = 'it',
    String? roomId,
    bool matureVisibleToMinors = true,
  }) =>
      IncompleteStoriesViewModel(
        storyRepository: stories,
        authRepository: FakeAuthRepository(email: _me),
        ageGate: gate,
        language: language,
        roomId: roomId,
        now: () => now,
        matureVisibleToMinors: matureVisibleToMinors,
      );

  /// The ViewModel with the stored birth year read and the list loaded.
  Future<IncompleteStoriesViewModel> loaded({
    bool matureVisibleToMinors = true,
  }) async {
    final viewModel = create(matureVisibleToMinors: matureVisibleToMinors);
    await pumpEventQueue();
    return viewModel;
  }

  void storeMinorYear() {
    ages = FakeAgeCheckRepository(birthYears: {_me: 2015});
    gate = _CountingGate(signals: source, storage: ages, clock: () => now);
  }

  IncompleteStoryStatus statusOf(
          IncompleteStoriesViewModel viewModel, String id) =>
      viewModel.statusOf(viewModel.stories!.firstWhere((s) => s.id == id));

  test('loads the room stories, least written first', () async {
    stories = FakeStoryRepository(stories: [
      story('two', authors: [_other, _me]),
      story('none'),
      story('one', authors: [_other]),
      story('english', language: 'en'),
    ]);
    final viewModel = create();
    expect(viewModel.stories, isNull);

    await pumpEventQueue();

    expect(viewModel.stories!.map((s) => s.id), ['none', 'one', 'two']);
  });

  test('tells which stories the user can open', () async {
    stories = FakeStoryRepository(stories: [
      story('free', authors: [_other]),
      story('locked', lockedBy: _other, lockedAt: now),
      story('expired',
          lockedBy: _other, lockedAt: now.subtract(Story.lockDuration)),
      story('mine', authors: [_me]),
      story('my lock', lockedBy: _me, lockedAt: now),
    ]);
    final viewModel = create();
    await pumpEventQueue();

    final byId = {for (final s in viewModel.stories!) s.id: s};
    expect(viewModel.statusOf(byId['free']!), IncompleteStoryStatus.available);
    expect(viewModel.statusOf(byId['locked']!),
        IncompleteStoryStatus.beingWritten);
    expect(
        viewModel.statusOf(byId['expired']!), IncompleteStoryStatus.available);
    expect(viewModel.statusOf(byId['mine']!),
        IncompleteStoryStatus.waitingForOthers);
    expect(
        viewModel.statusOf(byId['my lock']!), IncompleteStoryStatus.available);
  });

  test('switching room shows that room only', () async {
    stories = FakeStoryRepository(stories: [
      story('public'),
      story('private', roomId: 'friends'),
    ]);
    final viewModel = create();
    await pumpEventQueue();

    viewModel.setRoom(language: 'it', roomId: 'friends');
    expect(viewModel.stories, isNull);
    await pumpEventQueue();

    expect(viewModel.stories!.map((s) => s.id), ['private']);
  });

  test('setting the same room keeps the list', () async {
    stories = FakeStoryRepository(stories: [story('public')]);
    final viewModel = create();
    await pumpEventQueue();
    var notified = false;
    viewModel.addListener(() => notified = true);

    viewModel.setRoom(language: 'it');

    expect(notified, isFalse);
    expect(viewModel.stories, hasLength(1));
  });

  test('creates a story in the current room and lists it', () async {
    stories = FakeStoryRepository();
    final viewModel = create(roomId: 'friends');
    await pumpEventQueue();

    await viewModel.createStory.execute();
    await pumpEventQueue();

    final created = viewModel.createStory.value!;
    expect(created.roomId, 'friends');
    expect(viewModel.stories!.map((s) => s.id), [created.id]);
  });

  test('a user whose introduction waits for its second part cannot create',
      () async {
    stories = FakeStoryRepository(stories: [
      story('mine', authors: [_me])
    ]);
    final viewModel = create();
    expect(viewModel.canCreateStory, isFalse);
    await pumpEventQueue();

    expect(viewModel.canCreateStory, isFalse);
  });

  test(
      'a user can create once their introduction is continued, or when '
      'someone else wrote it', () async {
    stories = FakeStoryRepository(stories: [
      story('continued', authors: [_me, _other]),
      story('theirs', authors: [_other]),
      story('other room', authors: [_me], roomId: 'friends'),
    ]);
    final viewModel = create();
    await pumpEventQueue();

    expect(viewModel.canCreateStory, isTrue);
  });

  test('creating reuses an empty story the user can open', () async {
    stories = FakeStoryRepository(stories: [
      story('locked', lockedBy: _other, lockedAt: now),
      story('empty'),
    ]);
    final viewModel = create();
    await pumpEventQueue();

    await viewModel.createStory.execute();

    expect(viewModel.createStory.value!.id, 'empty');
    expect(stories.stories, hasLength(2));
  });

  test('a failed creation is reported', () async {
    stories = FakeStoryRepository()..failWith = Exception('offline');
    final viewModel = create();

    await viewModel.createStory.execute();

    expect(viewModel.createStory.error, isA<Exception>());
    expect(viewModel.createStory.completed, isFalse);
  });

  group('review and mature states, first match wins', () {
    test('a story whose last part awaits review is under review', () async {
      stories = FakeStoryRepository(stories: [
        story('pending', authors: [_other], reviewed: false),
        story('earlier pending', authors: [_other, _other], reviewed: false),
        story('empty'),
      ]);
      final viewModel = await loaded();

      expect(statusOf(viewModel, 'pending'), IncompleteStoryStatus.underReview);
      expect(statusOf(viewModel, 'earlier pending'),
          IncompleteStoryStatus.underReview);
      // Nothing to review without parts.
      expect(statusOf(viewModel, 'empty'), IncompleteStoryStatus.available);
    });

    test(
        'under review beats waiting for others, until the verdict arrives '
        'on the stream', () async {
      final mine = story('mine', authors: [_me], reviewed: false);
      stories = FakeStoryRepository(stories: [mine]);
      final viewModel = await loaded();

      expect(statusOf(viewModel, 'mine'), IncompleteStoryStatus.underReview);

      stories.put(reviewed(mine));
      await pumpEventQueue();

      expect(
          statusOf(viewModel, 'mine'), IncompleteStoryStatus.waitingForOthers);
    });

    test('under review beats being written', () async {
      stories = FakeStoryRepository(stories: [
        story('pending',
            authors: [_other],
            reviewed: false,
            lockedBy: _other,
            lockedAt: now),
      ]);
      final viewModel = await loaded();

      expect(statusOf(viewModel, 'pending'), IncompleteStoryStatus.underReview);
    });

    test(
        'unknown age: a mature story is locked, and being written or '
        'waiting keep their status with the locked mature state', () async {
      stories = FakeStoryRepository(stories: [
        story('mature', authors: [_other], mature: true),
        story('taken',
            authors: [_other], mature: true, lockedBy: _other, lockedAt: now),
        story('mine', authors: [_other, _me], mature: true),
      ]);
      final viewModel = await loaded();

      expect(statusOf(viewModel, 'mature'), IncompleteStoryStatus.locked);
      expect(statusOf(viewModel, 'taken'), IncompleteStoryStatus.beingWritten);
      expect(
          statusOf(viewModel, 'mine'), IncompleteStoryStatus.waitingForOthers);
      for (final s in viewModel.stories!) {
        expect(viewModel.matureStateOf(s), MatureTileState.locked);
      }
    });

    test(
        'a known minor: a mature story is unavailable, even under review or '
        'being written', () async {
      storeMinorYear();
      stories = FakeStoryRepository(stories: [
        story('mature', authors: [_other], mature: true),
        story('pending',
            authors: [_other, _other], mature: true, reviewed: false),
        story('taken',
            authors: [_other], mature: true, lockedBy: _other, lockedAt: now),
        story('clean', authors: [_other]),
      ]);
      final viewModel = await loaded();

      expect(statusOf(viewModel, 'mature'), IncompleteStoryStatus.unavailable);
      expect(statusOf(viewModel, 'pending'), IncompleteStoryStatus.unavailable);
      expect(statusOf(viewModel, 'taken'), IncompleteStoryStatus.unavailable);
      expect(statusOf(viewModel, 'clean'), IncompleteStoryStatus.available);
    });

    test('while the stored-year read runs, a mature story is locked', () async {
      storeMinorYear();
      final read = Completer<int?>();
      gate.read = read.future;
      stories = FakeStoryRepository(stories: [
        story('mature', authors: [_other], mature: true),
      ]);
      final viewModel = await loaded();

      expect(statusOf(viewModel, 'mature'), IncompleteStoryStatus.locked);

      read.complete(2015);
      await pumpEventQueue();
      expect(statusOf(viewModel, 'mature'), IncompleteStoryStatus.unavailable);
    });

    test('a session adult: a mature story is available, unlocked', () async {
      stories = FakeStoryRepository(stories: [
        story('mature', authors: [_other], mature: true),
      ]);
      gate.rememberVerdict(_me, adult: true);
      final viewModel = await loaded();
      final mature = viewModel.stories!.single;

      expect(viewModel.statusOf(mature), IncompleteStoryStatus.available);
      expect(viewModel.matureStateOf(mature), MatureTileState.unlocked);
    });

    test(
        'the live stream turns under review into available, locked or '
        'unavailable', () async {
      final safe = story('safe', authors: [_other], reviewed: false);
      final flagged = story('flagged', authors: [_other], reviewed: false);
      stories = FakeStoryRepository(stories: [safe, flagged]);
      final viewModel = await loaded();
      expect(statusOf(viewModel, 'safe'), IncompleteStoryStatus.underReview);
      expect(statusOf(viewModel, 'flagged'), IncompleteStoryStatus.underReview);

      stories.put(reviewed(safe));
      stories.put(reviewed(flagged, verdict: PartVerdict.mature));
      await pumpEventQueue();

      expect(statusOf(viewModel, 'safe'), IncompleteStoryStatus.available);
      expect(statusOf(viewModel, 'flagged'), IncompleteStoryStatus.locked);

      // For a known minor the flagged one turns unavailable instead.
      storeMinorYear();
      final minorStories = FakeStoryRepository(stories: [flagged]);
      stories = minorStories;
      final minorView = await loaded();
      expect(statusOf(minorView, 'flagged'), IncompleteStoryStatus.underReview);
      minorStories.put(reviewed(flagged, verdict: PartVerdict.mature));
      await pumpEventQueue();
      expect(statusOf(minorView, 'flagged'), IncompleteStoryStatus.unavailable);
    });
  });

  group('mature stories hidden from minors (flag off)', () {
    List<String> ids(IncompleteStoriesViewModel viewModel) =>
        [for (final s in viewModel.stories!) s.id];

    test('a known minor: mature stories are not listed, whatever their state',
        () async {
      storeMinorYear();
      stories = FakeStoryRepository(stories: [
        story('mature', authors: [_other], mature: true),
        story('pending',
            authors: [_other, _other], mature: true, reviewed: false),
        story('taken',
            authors: [_other], mature: true, lockedBy: _other, lockedAt: now),
        story('clean', authors: [_other]),
      ]);
      final viewModel = await loaded(matureVisibleToMinors: false);

      expect(ids(viewModel), ['clean']);
      expect(statusOf(viewModel, 'clean'), IncompleteStoryStatus.available);
    });

    test('a known minor in a room of mature stories only gets an empty list',
        () async {
      storeMinorYear();
      stories = FakeStoryRepository(stories: [
        story('mature', authors: [_other], mature: true),
      ]);
      final viewModel = await loaded(matureVisibleToMinors: false);

      expect(viewModel.stories, isEmpty);
    });

    test('while the stored-year read runs, a mature story is listed, locked',
        () async {
      storeMinorYear();
      final read = Completer<int?>();
      gate.read = read.future;
      stories = FakeStoryRepository(stories: [
        story('mature', authors: [_other], mature: true),
        story('clean', authors: [_other]),
      ]);
      final viewModel = await loaded(matureVisibleToMinors: false);

      expect(ids(viewModel), unorderedEquals(['mature', 'clean']));
      expect(statusOf(viewModel, 'mature'), IncompleteStoryStatus.locked);

      read.complete(2015);
      await pumpEventQueue();
      expect(ids(viewModel), ['clean']);
    });

    test('a minor signal answers minor, then hides every mature story',
        () async {
      source.signal = AgeSignal.minor;
      final mature = story('mature', authors: [_other], mature: true);
      stories = FakeStoryRepository(stories: [
        mature,
        story('other mature', authors: [_other], mature: true),
        story('clean', authors: [_other]),
      ]);
      final viewModel = await loaded(matureVisibleToMinors: false);
      expect(ids(viewModel), hasLength(3));

      await viewModel.unlock.execute(mature);

      expect(viewModel.unlock.value!.outcome, UnlockOutcome.minor);
      expect(ids(viewModel), ['clean']);
      expect(viewModel.matureStateOf(mature), MatureTileState.hidden);
    });

    test('a hidden mature introduction still does not block a new story',
        () async {
      storeMinorYear();
      stories = FakeStoryRepository(stories: [
        story('mine', authors: [_me], mature: true),
      ]);
      final viewModel = await loaded(matureVisibleToMinors: false);

      expect(viewModel.stories, isEmpty);
      expect(viewModel.canCreateStory, isTrue);
    });

    test('unknown age: a mature story is listed and locked', () async {
      stories = FakeStoryRepository(stories: [
        story('mature', authors: [_other], mature: true),
      ]);
      final viewModel = await loaded(matureVisibleToMinors: false);

      expect(statusOf(viewModel, 'mature'), IncompleteStoryStatus.locked);
    });
  });

  group('unlock', () {
    test('a known minor gets minor without the gate', () async {
      storeMinorYear();
      final mature = story('mature', authors: [_other], mature: true);
      stories = FakeStoryRepository(stories: [mature]);
      final viewModel = await loaded();

      await viewModel.unlock.execute(mature);

      expect(viewModel.unlock.value!.outcome, UnlockOutcome.minor);
      expect(gate.resolves, 0);
    });

    test('an adult opens the latest version of the story', () async {
      final mature = story('mature', authors: [_other], mature: true);
      stories = FakeStoryRepository(stories: [mature]);
      final viewModel = await loaded();
      final newer = story('mature',
          authors: [_other], mature: true, lockedBy: _other, lockedAt: now);
      stories.put(newer);
      await pumpEventQueue();

      await viewModel.unlock.execute(mature);

      expect(viewModel.unlock.value!.outcome, UnlockOutcome.open);
      expect(viewModel.unlock.value!.story.lockedBy, _other);
      expect(viewModel.matureStateOf(newer), MatureTileState.unlocked);
    });

    test('a minor signal turns every mature story unavailable', () async {
      source.signal = AgeSignal.minor;
      final mature = story('mature', authors: [_other], mature: true);
      stories = FakeStoryRepository(stories: [
        mature,
        story('other mature', authors: [_other], mature: true),
      ]);
      final viewModel = await loaded();

      await viewModel.unlock.execute(mature);

      expect(viewModel.unlock.value!.outcome, UnlockOutcome.minor);
      for (final s in viewModel.stories!) {
        expect(viewModel.statusOf(s), IncompleteStoryStatus.unavailable);
      }
    });

    test('no signal asks the birth year, then decides with it', () async {
      source.signal = AgeSignal.unavailable;
      final mature = story('mature', authors: [_other], mature: true);
      stories = FakeStoryRepository(stories: [mature]);
      final viewModel = await loaded();

      await viewModel.unlock.execute(mature);
      expect(viewModel.unlock.value!.outcome, UnlockOutcome.askBirthYear);
      expect(viewModel.checkingStoryId, 'mature');

      await viewModel.submitBirthYear.execute(1990);

      expect(viewModel.submitBirthYear.value!.outcome, UnlockOutcome.open);
      expect(viewModel.checkingStoryId, isNull);
      expect(await ages.getBirthYear(_me), 1990);
    });
  });

  test(
      'a known minor\'s own flagged introduction is listed as unavailable '
      'and does not block creating a story', () async {
    storeMinorYear();
    stories = FakeStoryRepository(stories: [
      story('mine', authors: [_me], mature: true),
    ]);
    final viewModel = await loaded();

    expect(statusOf(viewModel, 'mine'), IncompleteStoryStatus.unavailable);
    expect(viewModel.canCreateStory, isTrue);

    await viewModel.createStory.execute();
    await pumpEventQueue();
    expect(viewModel.stories, hasLength(2));
  });

  test('stops listening once disposed', () async {
    stories = FakeStoryRepository();
    final viewModel = create();
    await pumpEventQueue();

    viewModel.dispose();
    await stories.createStory(language: 'it');
    await pumpEventQueue();
    // No "used after being disposed" error was thrown.
  });
}
