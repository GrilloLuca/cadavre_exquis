import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/ui/incomplete_stories/view_models/incomplete_stories_view_model.dart';

import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_story_repository.dart';

const _me = 'me@example.com';
const _other = 'other@example.com';

void main() {
  final now = DateTime.utc(2026, 10, 12, 10);

  StoryPart part(String author) => StoryPart(
      position: 'introduzione', text: 'x', author: author, timestamp: now);

  Story story(
    String id, {
    List<String> authors = const [],
    String? lockedBy,
    DateTime? lockedAt,
    String language = 'it',
    String? roomId,
  }) =>
      Story(
        id: id,
        status: 'incomplete',
        currentPosition: kStoryPositions[authors.length],
        parts: [for (final author in authors) part(author)],
        lockedBy: lockedBy,
        lockedAt: lockedAt,
        language: language,
        roomId: roomId,
      );

  late FakeStoryRepository stories;

  IncompleteStoriesViewModel create({String language = 'it', String? roomId}) =>
      IncompleteStoriesViewModel(
        storyRepository: stories,
        authRepository: FakeAuthRepository(email: _me),
        language: language,
        roomId: roomId,
        now: () => now,
      );

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

  test('a failed creation is reported', () async {
    stories = FakeStoryRepository()..failWith = Exception('offline');
    final viewModel = create();

    await viewModel.createStory.execute();

    expect(viewModel.createStory.error, isA<Exception>());
    expect(viewModel.createStory.completed, isFalse);
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
