/// What a push notification about a story says happened to it.
enum StoryNotificationKind {
  /// Someone wrote the next part of a story the user wrote in.
  continued('story_continued'),

  /// A story the user wrote in is complete and reviewed, ready to read.
  completed('story_completed');

  const StoryNotificationKind(this.wireName);

  /// The `type` the Cloud Functions put in the message data. Must match
  /// `NotificationKind` in functions/src/notifications.ts.
  final String wireName;
}

/// A push notification about a story, received or tapped.
class StoryNotification {
  const StoryNotification({
    required this.kind,
    required this.storyId,
    this.title,
    this.body,
  });

  final StoryNotificationKind kind;
  final String storyId;

  /// The text the system showed, already localized by the server. Null when
  /// the message had none.
  final String? title;
  final String? body;

  /// The notification described by a message's [data], or null if it isn't
  /// one of ours (unknown type, no story id).
  static StoryNotification? fromData(
    Map<String, dynamic> data, {
    String? title,
    String? body,
  }) {
    final type = data['type'];
    final storyId = data['storyId'];
    if (storyId is! String || storyId.isEmpty) return null;
    for (final kind in StoryNotificationKind.values) {
      if (kind.wireName == type) {
        return StoryNotification(
          kind: kind,
          storyId: storyId,
          title: title,
          body: body,
        );
      }
    }
    return null;
  }
}

/// Whether the device lets the app show notifications.
enum NotificationPermission {
  /// Allowed (including iOS provisional authorization).
  granted,

  /// The user refused; only the system settings can change it now.
  denied,

  /// Never asked: asking shows the system prompt.
  notDetermined,

  /// Push notifications don't exist on this platform (e.g. web).
  unsupported,
}
