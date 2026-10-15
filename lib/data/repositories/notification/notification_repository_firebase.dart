import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/notification/notification_repository.dart';
import 'package:cadavre_exquisite/data/services/notification_offer_preference.dart';
import 'package:cadavre_exquisite/data/services/push_messaging_service.dart';
import 'package:cadavre_exquisite/domain/models/email_key.dart';
import 'package:cadavre_exquisite/domain/models/story_notification.dart';

/// The language the app shows for [deviceLocales], which the server writes
/// the notifications in: the first device language the app has, as
/// Flutter's locale resolution picks it, otherwise English (the first of
/// `AppLocalizations.supportedLocales`).
String notificationLocale(List<Locale> deviceLocales) {
  const supported = ['en', 'it'];
  for (final locale in deviceLocales) {
    if (supported.contains(locale.languageCode)) return locale.languageCode;
  }
  return supported.first;
}

/// [NotificationRepository] on Firebase Cloud Messaging. The device's
/// token is stored in `pushTokens/{token}` with the user's [emailKey], so
/// the Cloud Functions can find every device of a story's authors (see
/// functions/src/notifications.ts).
class NotificationRepositoryFirebase extends NotificationRepository {
  NotificationRepositoryFirebase({
    required AuthRepository authRepository,
    PushMessagingService? messaging,
    NotificationOfferPreference? offerPreference,
    FirebaseFirestore? firestore,
    List<Locale> Function()? deviceLocales,
  })  : _auth = authRepository,
        _messaging = messaging ?? PushMessagingService(),
        _offer = offerPreference ?? NotificationOfferPreference(),
        _firestoreOverride = firestore,
        _deviceLocales = deviceLocales ??
            (() => WidgetsBinding.instance.platformDispatcher.locales) {
    if (!_messaging.isSupported) {
      _permission = NotificationPermission.unsupported;
      return;
    }
    _auth.addListener(_onAuthChanged);
    _tokenRefresh = _messaging.onTokenRefresh.listen(
      (token) => _register(token: token),
      onError: (Object _) {},
    );
    unawaited(refreshPermission().catchError((Object _) {
      return NotificationPermission.notDetermined;
    }));
  }

  final AuthRepository _auth;
  final PushMessagingService _messaging;
  final NotificationOfferPreference _offer;
  final FirebaseFirestore? _firestoreOverride;
  final List<Locale> Function() _deviceLocales;
  StreamSubscription<String>? _tokenRefresh;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  NotificationPermission? _permission;

  /// The token stored for [_registeredFor], if any.
  String? _registeredToken;
  String? _registeredFor;

  bool _launchTaken = false;

  /// Set by [unregister] until the user signs out, so a token refresh in
  /// between (deleting the token issues a new one) can't register the
  /// leaving user again.
  bool _suspended = false;

  @override
  NotificationPermission? get permission => _permission;

  void _setPermission(NotificationPermission permission) {
    if (permission == _permission) return;
    _permission = permission;
    notifyListeners();
  }

  void _onAuthChanged() {
    final email = _auth.currentEmail;
    if (email == null) {
      // Signed out: the token document was deleted by [unregister], if the
      // caller remembered to; there's no user left to delete it as.
      _registeredToken = null;
      _registeredFor = null;
      _suspended = false;
    } else if (email != _registeredFor &&
        _permission == NotificationPermission.granted) {
      unawaited(_register());
    }
  }

  /// Stores [token] (by default the current one) for the signed-in user.
  /// Best effort: without the document the user just gets no
  /// notifications, and the next app start tries again.
  Future<void> _register({String? token}) async {
    final email = _auth.currentEmail;
    if (email == null ||
        _suspended ||
        _permission != NotificationPermission.granted) {
      return;
    }
    try {
      final current = token ?? await _messaging.getToken();
      // Unregistered while the token was being read.
      if (current == null || _suspended) return;
      await _firestore.collection('pushTokens').doc(current).set({
        'emailKey': emailKey(email),
        'locale': notificationLocale(_deviceLocales()),
        'platform': _messaging.platform,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _registeredToken = current;
      _registeredFor = email;
    } catch (_) {
      // E.g. offline, or no APNs token yet on iOS.
    }
  }

  /// The device's permission. Android has no "never asked" state and
  /// reports it as denied, so a denial before the app ever asked counts as
  /// not determined: the offer and the profile's button can still ask.
  Future<NotificationPermission> _readPermission() async {
    final permission = await _messaging.permission();
    if (permission == NotificationPermission.denied &&
        _messaging.platform == 'android' &&
        !await _offer.wasPermissionRequested()) {
      return NotificationPermission.notDetermined;
    }
    return permission;
  }

  @override
  Future<NotificationPermission> refreshPermission() async {
    if (!_messaging.isSupported) return NotificationPermission.unsupported;
    final permission = await _readPermission();
    _setPermission(permission);
    // Also refreshes `locale` and `updatedAt` on every start.
    if (permission == NotificationPermission.granted) await _register();
    return permission;
  }

  @override
  Future<NotificationPermission> enable() async {
    if (!_messaging.isSupported) return NotificationPermission.unsupported;
    try {
      await _offer.recordPermissionRequested();
    } catch (_) {}
    final permission = await _messaging.requestPermission();
    _setPermission(permission);
    if (permission == NotificationPermission.granted) await _register();
    return permission;
  }

  @override
  Future<bool> shouldOffer() async {
    try {
      final permission = await refreshPermission();
      if (permission != NotificationPermission.notDetermined) return false;
      return await _offer.shouldOffer(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> dismissOffer() async {
    try {
      await _offer.recordDismissal(DateTime.now());
    } catch (_) {
      // Offered again next time.
    }
  }

  @override
  Future<void> unregister() async {
    if (!_messaging.isSupported) return;
    _suspended = true;
    final token = _registeredToken;
    _registeredToken = null;
    _registeredFor = null;
    if (token == null && _permission != NotificationPermission.granted) {
      return;
    }
    try {
      final current = token ?? await _messaging.getToken();
      if (current != null) {
        await _firestore.collection('pushTokens').doc(current).delete();
      }
    } catch (_) {
      // Already gone, or offline: the server prunes it once FCM rejects it.
    }
    try {
      // A new token is issued at the next sign-in, so a document left
      // behind above can't reach the next user of this device.
      await _messaging.deleteToken();
    } catch (_) {}
  }

  @override
  Future<StoryNotification?> takeLaunchNotification() async {
    if (_launchTaken || !_messaging.isSupported) return null;
    _launchTaken = true;
    try {
      return await _messaging.initialNotification();
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<StoryNotification> get opened =>
      _messaging.isSupported ? _messaging.opened : const Stream.empty();

  @override
  Stream<StoryNotification> get received =>
      _messaging.isSupported ? _messaging.received : const Stream.empty();

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _tokenRefresh?.cancel();
    super.dispose();
  }
}
