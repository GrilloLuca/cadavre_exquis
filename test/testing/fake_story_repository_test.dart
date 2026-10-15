import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/domain/models/story.dart';

import '../../testing/fakes/repositories/fake_story_repository.dart';

void main() {
  late DateTime now;
  late FakeStoryRepository repository;

  setUp(() {
    now = DateTime.utc(2026, 10, 12, 10);
    repository = FakeStoryRepository(now: () => now);
  });

  Matcher throwsStory(StoryErrorCode code) =>
      throwsA(isA<StoryException>().having((e) => e.code, 'code', code));

  test('a story goes through every position and completes', () async {
    final story = await repository.createStory(language: 'it');
    final authors = ['a@x.it', 'b@x.it', 'a@x.it', 'b@x.it'];

    for (final (i, author) in authors.indexed) {
      await repository.lockStory(storyId: story.id, authorEmail: author);
      await repository.submitPart(
        storyId: story.id,
        expectedPosition: kStoryPositions[i],
        text: 'part $i',
        authorEmail: author,
      );
    }

    final stored = repository.stories[story.id]!;
    expect(stored.isComplete, isTrue);
    expect(stored.parts, hasLength(4));
    expect(stored.lockedBy, isNull);
  });

  test('applies the lock and turn rules', () async {
    final story = await repository.createStory(language: 'it');
    await repository.lockStory(storyId: story.id, authorEmail: 'a@x.it');

    expect(repository.lockStory(storyId: story.id, authorEmail: 'b@x.it'),
        throwsStory(StoryErrorCode.lockedByOther));

    now = now.add(Story.lockDuration);
    await repository.lockStory(storyId: story.id, authorEmail: 'b@x.it');
    await repository.submitPart(
      storyId: story.id,
      expectedPosition: kStoryPositions.first,
      text: 'hi',
      authorEmail: 'b@x.it',
    );

    expect(repository.lockStory(storyId: story.id, authorEmail: 'b@x.it'),
        throwsStory(StoryErrorCode.consecutiveTurnNotAllowed));
    expect(
        repository.submitPart(
          storyId: story.id,
          expectedPosition: kStoryPositions.first,
          text: 'again',
          authorEmail: 'a@x.it',
        ),
        throwsStory(StoryErrorCode.positionTaken));
  });

  test('keeps the keywords of a story through locks and submits', () async {
    // Like Firestore, where only extractStoryKeywords writes `keywords`.
    final repository = FakeStoryRepository(now: () => now, stories: [
      Story(
        id: 's1',
        status: 'incomplete',
        currentPosition: 'introduzione',
        parts: [],
        keywords: const ['drago', 'faro'],
      ),
    ]);

    await repository.lockStory(storyId: 's1', authorEmail: 'a@x.it');
    await repository.submitPart(
      storyId: 's1',
      expectedPosition: 'introduzione',
      text: 'part',
      authorEmail: 'a@x.it',
    );

    expect(repository.stories['s1']!.keywords, ['drago', 'faro']);
  });

  test('streams emit the current room and every change', () async {
    final emitted = <int>[];
    final subscription = repository
        .incompleteStoriesStream(language: 'it')
        .listen((stories) => emitted.add(stories.length));

    await repository.createStory(language: 'it');
    await repository.createStory(language: 'en');
    await repository.createStory(language: 'it', roomId: 'friends');
    await pumpEventQueue();

    expect(emitted, [0, 1, 1, 1]);
    await subscription.cancel();
  });
}
