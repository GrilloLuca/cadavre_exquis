import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/models/story_notification.dart';
import 'package:cadavre_exquisite/ui/chat/view_models/chat_view_model.dart';

import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_notification_repository.dart';
import '../../../testing/fakes/repositories/fake_safety_repository.dart';
import '../../../testing/fakes/repositories/fake_story_repository.dart';
import '../../../testing/fakes/repositories/fake_user_profile_repository.dart';

const _me = 'me@example.com';
const _other = 'other@example.com';

void main() {
  late DateTime now;
  late FakeStoryRepository stories;
  late FakeAuthRepository auth;
  late FakeNotificationRepository notifications;
  late FakeUserProfileRepository profiles;
  late FakeSafetyRepository safety;

  Story newStory({String? lockedBy}) => Story(
        id: 's1',
        status: 'incomplete',
        currentPosition: kStoryPositions.first,
        parts: const [],
        lockedBy: lockedBy,
        lockedAt: lockedBy == null ? null : now,
        language: 'it',
      );

  setUp(() {
    now = DateTime.utc(2026, 10, 12, 10);
    stories = FakeStoryRepository(stories: [newStory()], now: () => now);
    auth = FakeAuthRepository(email: _me);
    notifications = FakeNotificationRepository();
    profiles = FakeUserProfileRepository(nicknames: const {_other: 'Lupo'});
    safety = FakeSafetyRepository();
  });

  ChatViewModel create() => ChatViewModel(
        story: stories.stories['s1']!,
        storyRepository: stories,
        authRepository: auth,
        notificationRepository: notifications,
        profileRepository: profiles,
        safetyRepository: safety,
      );

  test('locks the story on creation, then lets the user write', () async {
    final viewModel = create();
    expect(viewModel.lock.running, isTrue);
    expect(viewModel.canWrite, isFalse);

    await pumpEventQueue();

    expect(viewModel.lock.completed, isTrue);
    expect(viewModel.canWrite, isTrue);
    expect(stories.stories['s1']!.lockedBy, _me);
  });

  test('a story locked by someone else fails the lock', () async {
    stories = FakeStoryRepository(
        stories: [newStory(lockedBy: _other)], now: () => now);
    final viewModel = create();
    await pumpEventQueue();

    expect(
        viewModel.lock.error,
        isA<StoryException>()
            .having((e) => e.code, 'code', StoryErrorCode.lockedByOther));
    expect(viewModel.canWrite, isFalse);
  });

  test('without a signed-in user nothing is locked', () async {
    auth = FakeAuthRepository();
    final viewModel = create();
    await pumpEventQueue();

    expect(viewModel.canWrite, isFalse);
    expect(stories.stories['s1']!.lockedBy, isNull);
  });

  test('submits the trimmed text and gives the lock back', () async {
    final viewModel = create();
    await pumpEventQueue();

    await viewModel.submit.execute('  Once upon a time there  ');

    expect(viewModel.submit.value, isTrue);
    final stored = stories.stories['s1']!;
    expect(stored.parts.single.text, 'Once upon a time there');
    expect(stored.parts.single.author, _me);
    expect(stored.currentPosition, kStoryPositions[1]);
    expect(stored.lockedBy, isNull);
    expect(viewModel.canWrite, isFalse);
  });

  test('blank text sends nothing', () async {
    final viewModel = create();
    await pumpEventQueue();

    await viewModel.submit.execute('   ');

    expect(viewModel.submit.value, isFalse);
    expect(stories.stories['s1']!.parts, isEmpty);
    expect(viewModel.canWrite, isTrue);
  });

  test('fewer than five words send nothing', () async {
    final viewModel = create();
    await pumpEventQueue();

    await viewModel.submit.execute('ijhodfaxòklo');
    await viewModel.submit.execute(' once upon a\ntime ');

    expect(viewModel.submit.value, isFalse);
    expect(stories.stories['s1']!.parts, isEmpty);
    expect(viewModel.canWrite, isTrue);
  });

  test('a failed submit keeps the lock so the user can retry', () async {
    final viewModel = create();
    await pumpEventQueue();
    stories.failWith = const StoryException(StoryErrorCode.positionTaken);

    await viewModel.submit.execute('hello there my dear friend');

    expect(viewModel.submit.error, isA<StoryException>());
    expect(viewModel.canWrite, isTrue);
    expect(stories.stories['s1']!.lockedBy, _me);
  });

  test('dispose gives the lock back when nothing was submitted', () async {
    final viewModel = create();
    await pumpEventQueue();

    viewModel.dispose();
    await pumpEventQueue();

    expect(stories.stories['s1']!.lockedBy, isNull);
  });

  test('dispose after submitting does not touch the story', () async {
    final viewModel = create();
    await pumpEventQueue();
    await viewModel.submit.execute('hello there my dear friend');
    // Someone else takes the next turn, once reviewed, before the screen
    // closes.
    stories.review('s1');
    await stories.lockStory(storyId: 's1', authorEmail: _other);

    viewModel.dispose();
    await pumpEventQueue();

    expect(stories.stories['s1']!.lockedBy, _other);
  });

  test('closing while the lock is in flight gives it back once taken',
      () async {
    final viewModel = create();

    viewModel.dispose();
    await pumpEventQueue();

    expect(stories.stories['s1']!.lockedBy, isNull);
  });

  group('previous author', () {
    StoryPart introduction() => StoryPart(
          position: kStoryPositions.first,
          text: 'Un drago viveva nel faro',
          author: _other,
          timestamp: now,
        );

    Story continuedStory() => Story(
          id: 's1',
          status: 'incomplete',
          currentPosition: kStoryPositions[1],
          parts: [introduction()],
          language: 'it',
          partReviews: {kStoryPositions.first: PartVerdict.safe},
        );

    test('is masked until the nickname loads, then named by it', () async {
      stories =
          FakeStoryRepository(stories: [continuedStory()], now: () => now);
      final viewModel = create();
      expect(viewModel.previousPart?.author, _other);
      expect(viewModel.previousAuthorName, 'ot***');

      await pumpEventQueue();

      expect(viewModel.previousAuthorName, 'Lupo');
    });

    test('keeps the masked email when the lookup fails', () async {
      stories =
          FakeStoryRepository(stories: [continuedStory()], now: () => now);
      profiles.failWith = Exception('offline');
      final viewModel = create();
      await pumpEventQueue();

      expect(viewModel.loadPreviousAuthor.error, isNull);
      expect(viewModel.previousAuthorName, 'ot***');
    });

    test('is absent for a story without parts', () async {
      final viewModel = create();
      await pumpEventQueue();

      expect(viewModel.previousPart, isNull);
      expect(viewModel.previousAuthorName, isNull);
    });
  });

  group('notification offer', () {
    test('is made after a part is sent when the user was never asked',
        () async {
      notifications = FakeNotificationRepository(
        permission: NotificationPermission.notDetermined,
        offer: true,
      );
      final viewModel = create();
      await pumpEventQueue();
      expect(viewModel.offerNotifications, isFalse);

      await viewModel.submit.execute('hello there my dear friend');

      expect(viewModel.offerNotifications, isTrue);
      await viewModel.answerNotificationOffer.execute(true);
      expect(notifications.calls, ['enable']);
      expect(viewModel.offerNotifications, isFalse);
      viewModel.dispose();
    });

    test('"Not now" is remembered', () async {
      notifications = FakeNotificationRepository(
        permission: NotificationPermission.notDetermined,
        offer: true,
      );
      final viewModel = create();
      await pumpEventQueue();
      await viewModel.submit.execute('hello there my dear friend');

      await viewModel.answerNotificationOffer.execute(false);

      expect(notifications.calls, ['dismissOffer']);
      viewModel.dispose();
    });

    test('is not made once the user answered the system prompt', () async {
      notifications = FakeNotificationRepository(
        permission: NotificationPermission.denied,
        offer: true,
      );
      final viewModel = create();
      await pumpEventQueue();

      await viewModel.submit.execute('hello there my dear friend');

      expect(viewModel.submit.value, isTrue);
      expect(viewModel.offerNotifications, isFalse);
      viewModel.dispose();
    });
  });
}
