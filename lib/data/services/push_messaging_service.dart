import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/domain/models/story_notification.dart';

/// Thin wrapper over [FirebaseMessaging] (FCM), turning its messages into
/// [StoryNotification]s. Messages that aren't about a story are dropped.
class PushMessagingService {
  PushMessagingService({FirebaseMessaging? messaging})
      : _messagingOverride = messaging;

  final FirebaseMessaging? _messagingOverride;

  /// Created lazily: [FirebaseMessaging.instance] needs an initialized
  /// Firebase app, and the platform may not support push at all.
  FirebaseMessaging get _messaging =>
      _messagingOverride ?? FirebaseMessaging.instance;

  /// Whether this platform gets push notifications: Android and iOS only.
  /// Web push needs a service worker and a VAPID key the app doesn't have.
  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// `android` or `ios`, as stored with the token.
  String get platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  Future<NotificationPermission> permission() async {
    if (!isSupported) return NotificationPermission.unsupported;
    final settings = await _messaging.getNotificationSettings();
    return _permissionOf(settings.authorizationStatus);
  }

  /// Shows the system prompt if the user was never asked, and returns the
  /// resulting permission.
  Future<NotificationPermission> requestPermission() async {
    if (!isSupported) return NotificationPermission.unsupported;
    final settings = await _messaging.requestPermission();
    return _permissionOf(settings.authorizationStatus);
  }

  Future<String?> getToken() => _messaging.getToken();

  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  Future<void> deleteToken() => _messaging.deleteToken();

  /// The notification whose tap launched the app, if any.
  Future<StoryNotification?> initialNotification() async =>
      _toNotification(await _messaging.getInitialMessage());

  /// Taps on a notification while the app was in the background.
  Stream<StoryNotification> get opened => FirebaseMessaging.onMessageOpenedApp
      .map(_toNotification)
      .where((n) => n != null)
      .cast<StoryNotification>();

  /// Notifications arriving while the app is in the foreground, which the
  /// system doesn't show.
  Stream<StoryNotification> get received => FirebaseMessaging.onMessage
      .map(_toNotification)
      .where((n) => n != null)
      .cast<StoryNotification>();

  static StoryNotification? _toNotification(RemoteMessage? message) {
    if (message == null) return null;
    return StoryNotification.fromData(
      message.data,
      title: message.notification?.title,
      body: message.notification?.body,
    );
  }

  static NotificationPermission _permissionOf(AuthorizationStatus status) =>
      switch (status) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional =>
          NotificationPermission.granted,
        AuthorizationStatus.denied => NotificationPermission.denied,
        AuthorizationStatus.notDetermined =>
          NotificationPermission.notDetermined,
      };
}
