import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cadavre_exquisite/models/story_language.dart';

/// The room matching the user's device languages: the first locale (in the
/// user's order of preference) whose language has a room, otherwise
/// [kFallbackRoomLanguage]. Only the language code counts, so `pt_BR` does
/// not match anything and `de_AT` matches `de`.
String detectRoomLanguage(List<Locale> deviceLocales) =>
    detectRoomLanguageWithSource(deviceLocales).code;

/// [detectRoomLanguage], also telling whether a device locale matched
/// ([RoomLanguageSource.detected]) or the fallback was used.
({String code, RoomLanguageSource source}) detectRoomLanguageWithSource(
  List<Locale> deviceLocales,
) {
  for (final locale in deviceLocales) {
    final code = locale.languageCode;
    if (kStoryLanguages.any((language) => language.code == code)) {
      return (code: code, source: RoomLanguageSource.detected);
    }
  }
  return (code: kFallbackRoomLanguage, source: RoomLanguageSource.fallback);
}

/// Where a resolved language room came from: the user's stored choice, a
/// device locale that has a room, or [kFallbackRoomLanguage] because none
/// does. The Account screen explains the last two with a caption.
enum RoomLanguageSource { explicit, detected, fallback }

/// Which language room the user is in, kept on the device.
///
/// Only an explicit choice is stored. Until the user picks a room, the room
/// is detected from the device locales on every launch, so changing the
/// phone's language moves an undecided user to the matching room.
class LanguageRoomPreference {
  /// [prefs] and [deviceLocales] are injectable for tests only.
  LanguageRoomPreference({
    SharedPreferences? prefs,
    List<Locale> Function()? deviceLocales,
  })  : _prefs = prefs,
        _deviceLocales = deviceLocales ??
            (() => WidgetsBinding.instance.platformDispatcher.locales);

  static const String prefsKey = 'languageRoom';

  final SharedPreferences? _prefs;
  final List<Locale> Function() _deviceLocales;

  Future<SharedPreferences> _instance() async =>
      _prefs ?? await SharedPreferences.getInstance();

  /// The stored explicit choice if it is still a supported room, otherwise
  /// the detected one. Never writes: detection must run again next launch.
  Future<String> resolve() async => (await resolveWithSource()).code;

  /// Like [resolve], also telling whether the room was chosen, detected or
  /// is the fallback.
  Future<({String code, RoomLanguageSource source})>
      resolveWithSource() async {
    final prefs = await _instance();
    final stored = prefs.getString(prefsKey);
    if (stored != null &&
        kStoryLanguages.any((language) => language.code == stored)) {
      return (code: stored, source: RoomLanguageSource.explicit);
    }
    return detectRoomLanguageWithSource(_deviceLocales());
  }

  /// Records [code] as the user's explicit choice, which from now on wins
  /// over detection.
  Future<void> saveExplicit(String code) async {
    final prefs = await _instance();
    await prefs.setString(prefsKey, code);
  }
}
