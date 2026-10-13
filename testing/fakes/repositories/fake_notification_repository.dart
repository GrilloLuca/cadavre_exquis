import 'dart:async';

import 'package:cadavre_exquisite/data/repositories/notification/notification_repository.dart';
import 'package:cadavre_exquisite/domain/models/story_notification.dart';

/// In-memory [NotificationRepository] for ViewModel and widget tests.
/// Starts [NotificationPermission.unsupported] by default, so screens that
/// don't test notifications look as before them. [enable] grants
/// [permissionOnEnable]; [tap] and [receive] simulate notifications.
/// Records what was called in [calls].
class FakeNotificationRepository extends NotificationRepository {
  FakeNotificationRepository({
    NotificationPermission permission = NotificationPermission.unsupported,
    this.permissionOnEnable = NotificationPermission.granted,
    this.offer = false,
    this.launchNotification,
  }) : _permission = permission;

  NotificationPermission? _permission;

  /// What [enable] turns the permission into.
  NotificationPermission permissionOnEnable;

  /// What [shouldOffer] answers.
  bool offer;

  /// Returned once by [takeLaunchNotification].
  StoryNotification? launchNotification;

  /// `'enable'`, `'dismissOffer'`, `'unregister'`, in order.
  final List<String> calls = [];

  final _opened = StreamController<StoryNotification>.broadcast();
  final _received = StreamController<StoryNotification>.broadcast();

  /// Simulates a tap on [notification] while the app is in the background.
  void tap(StoryNotification notification) => _opened.add(notification);

  /// Simulates [notification] arriving while the app is in the foreground.
  void receive(StoryNotification notification) => _received.add(notification);

  @override
  NotificationPermission? get permission => _permission;

  @override
  Future<NotificationPermission> refreshPermission() async => _permission!;

  @override
  Future<NotificationPermission> enable() async {
    calls.add('enable');
    _permission = permissionOnEnable;
    notifyListeners();
    return _permission!;
  }

  @override
  Future<bool> shouldOffer() async =>
      offer && _permission == NotificationPermission.notDetermined;

  @override
  Future<void> dismissOffer() async => calls.add('dismissOffer');

  @override
  Future<void> unregister() async => calls.add('unregister');

  @override
  Future<StoryNotification?> takeLaunchNotification() async {
    final notification = launchNotification;
    launchNotification = null;
    return notification;
  }

  @override
  Stream<StoryNotification> get opened => _opened.stream;

  @override
  Stream<StoryNotification> get received => _received.stream;
}
