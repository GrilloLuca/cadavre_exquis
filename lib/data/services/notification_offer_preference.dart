import 'package:shared_preferences/shared_preferences.dart';

/// How often the app offers to turn on notifications after a part is
/// written, if the user hasn't answered the system prompt yet.
///
/// Offered until the user says "Not now" [maxDismissals] times, waiting at
/// least [retryAfter] after each "Not now".
class NotificationOfferPolicy {
  static const int maxDismissals = 2;
  static const Duration retryAfter = Duration(days: 7);

  /// Whether to offer now, given how many times the offer was dismissed and
  /// when it last was.
  static bool shouldOffer({
    required int dismissals,
    required DateTime? lastDismissedAt,
    required DateTime now,
  }) {
    if (dismissals <= 0 || lastDismissedAt == null) return true;
    if (dismissals >= maxDismissals) return false;
    return !now.isBefore(lastDismissedAt.add(retryAfter));
  }
}

/// The user's "Not now" answers to the notification offer, and whether the
/// system permission prompt was ever shown, kept on the device.
class NotificationOfferPreference {
  /// [prefs] is injectable for tests only.
  NotificationOfferPreference({SharedPreferences? prefs}) : _prefs = prefs;

  static const String dismissalsKey = 'notificationOfferDismissals';
  static const String lastDismissedAtKey = 'notificationOfferDismissedAt';
  static const String permissionRequestedKey =
      'notificationPermissionRequested';

  final SharedPreferences? _prefs;

  Future<SharedPreferences> _instance() async =>
      _prefs ?? await SharedPreferences.getInstance();

  Future<bool> shouldOffer(DateTime now) async {
    final prefs = await _instance();
    final millis = prefs.getInt(lastDismissedAtKey);
    return NotificationOfferPolicy.shouldOffer(
      dismissals: prefs.getInt(dismissalsKey) ?? 0,
      lastDismissedAt:
          millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis),
      now: now,
    );
  }

  /// Whether the app ever asked for the permission on this device. Android
  /// reports a permission never asked for as denied, so this tells the two
  /// apart.
  Future<bool> wasPermissionRequested() async =>
      (await _instance()).getBool(permissionRequestedKey) ?? false;

  Future<void> recordPermissionRequested() async =>
      (await _instance()).setBool(permissionRequestedKey, true);

  Future<void> recordDismissal(DateTime now) async {
    final prefs = await _instance();
    await prefs.setInt(dismissalsKey, (prefs.getInt(dismissalsKey) ?? 0) + 1);
    await prefs.setInt(lastDismissedAtKey, now.millisecondsSinceEpoch);
  }
}
