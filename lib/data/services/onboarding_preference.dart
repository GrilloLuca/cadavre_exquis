import 'package:shared_preferences/shared_preferences.dart';

/// Whether the user has gone through the onboarding slides on this device.
class OnboardingPreference {
  /// [prefs] is injectable for tests only.
  OnboardingPreference({SharedPreferences? prefs}) : _prefs = prefs;

  static const String seenKey = 'onboardingSeen';

  final SharedPreferences? _prefs;

  Future<SharedPreferences> _instance() async =>
      _prefs ?? await SharedPreferences.getInstance();

  Future<bool> hasSeen() async =>
      (await _instance()).getBool(seenKey) ?? false;

  Future<void> markSeen() async => (await _instance()).setBool(seenKey, true);
}
