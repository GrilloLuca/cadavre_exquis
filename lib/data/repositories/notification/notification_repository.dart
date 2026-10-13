import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/domain/models/story_notification.dart';

/// Push notifications about the user's stories: the device's permission,
/// registering the device for the signed-in user, and the notifications the
/// user taps or receives in the foreground.
///
/// The device registers by itself whenever someone is signed in and the
/// permission is granted. It must be unregistered *before* signing out (see
/// [unregister]); afterwards there is no user left to do it as.
abstract class NotificationRepository extends ChangeNotifier {
  /// The permission as last read, null until known. Notifies when it
  /// changes.
  NotificationPermission? get permission;

  /// Reads the permission again (e.g. the user changed it in the system
  /// settings) and registers the device if it is now granted.
  Future<NotificationPermission> refreshPermission();

  /// Asks for the permission (showing the system prompt if the user was
  /// never asked) and registers the device if granted. Returns the
  /// resulting permission.
  Future<NotificationPermission> enable();

  /// Whether to offer turning notifications on after the user wrote a part:
  /// never asked, and the offer wasn't turned down recently. Never throws.
  Future<bool> shouldOffer();

  /// Remembers that the user turned the offer down ("Not now").
  Future<void> dismissOffer();

  /// Stops sending this device the signed-in user's notifications. Call it
  /// before signing out or deleting the account. Never throws: it must not
  /// block signing out.
  Future<void> unregister();

  /// The notification whose tap launched the app, the first time it is
  /// asked for; null afterwards or if there was none.
  Future<StoryNotification?> takeLaunchNotification();

  /// Taps on a notification while the app was running in the background.
  Stream<StoryNotification> get opened;

  /// Notifications arriving while the app is in the foreground, which the
  /// system doesn't show.
  Stream<StoryNotification> get received;
}
