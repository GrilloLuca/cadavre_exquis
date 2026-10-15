import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/domain/models/story_notification.dart';

void main() {
  test('reads the notifications the Cloud Functions send', () {
    final continued = StoryNotification.fromData(
      {'type': 'story_continued', 'storyId': 'abc'},
      title: 'Marta continued one of your stories',
    )!;
    expect(continued.kind, StoryNotificationKind.continued);
    expect(continued.storyId, 'abc');
    expect(continued.title, 'Marta continued one of your stories');

    expect(
      StoryNotification.fromData({'type': 'story_completed', 'storyId': 'x'})!
          .kind,
      StoryNotificationKind.completed,
    );
  });

  test('ignores messages that are not about a story', () {
    expect(StoryNotification.fromData({}), isNull);
    expect(
        StoryNotification.fromData({'type': 'promo', 'storyId': 'x'}), isNull);
    expect(StoryNotification.fromData({'type': 'story_continued'}), isNull);
    expect(
      StoryNotification.fromData({'type': 'story_continued', 'storyId': ''}),
      isNull,
    );
  });
}
