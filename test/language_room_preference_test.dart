import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cadavre_exquisite/models/story_language.dart';
import 'package:cadavre_exquisite/services/language_room_preference.dart';

Future<LanguageRoomPreference> _preference({
  Map<String, Object> stored = const {},
  List<Locale> locales = const [],
}) async {
  SharedPreferences.setMockInitialValues(stored);
  return LanguageRoomPreference(
    prefs: await SharedPreferences.getInstance(),
    deviceLocales: () => locales,
  );
}

void main() {
  group('detectRoomLanguage', () {
    test('returns the first device language with a room', () {
      expect(
        detectRoomLanguage(const [Locale('de', 'DE'), Locale('en', 'US')]),
        'de',
      );
    });

    test('skips device languages without a room', () {
      expect(
        detectRoomLanguage(const [Locale('pt', 'BR'), Locale('fr', 'FR')]),
        'fr',
      );
    });

    test('falls back when no device language has a room', () {
      expect(
        detectRoomLanguage(const [Locale('ja', 'JP')]),
        kFallbackRoomLanguage,
      );
      expect(kFallbackRoomLanguage, 'en');
    });

    test('falls back when there are no device locales', () {
      expect(detectRoomLanguage(const []), kFallbackRoomLanguage);
    });
  });

  group('LanguageRoomPreference.resolve', () {
    test('a stored explicit choice beats detection', () async {
      final preference = await _preference(
        stored: {LanguageRoomPreference.prefsKey: 'es'},
        locales: const [Locale('de', 'DE')],
      );
      expect(await preference.resolve(), 'es');
    });

    test('ignores a stored code that is not a room', () async {
      final preference = await _preference(
        stored: {LanguageRoomPreference.prefsKey: 'xx'},
        locales: const [Locale('de', 'DE')],
      );
      expect(await preference.resolve(), 'de');
    });

    test('detects without writing when nothing is stored', () async {
      final preference = await _preference(
        locales: const [Locale('fr', 'FR')],
      );
      expect(await preference.resolve(), 'fr');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('saveExplicit stores the choice for later launches', () async {
      final preference = await _preference(
        locales: const [Locale('de', 'DE')],
      );
      await preference.saveExplicit('it');
      expect(await preference.resolve(), 'it');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LanguageRoomPreference.prefsKey), 'it');
    });
  });

  group('LanguageRoomPreference.resolveWithSource', () {
    test('reports a stored choice as explicit', () async {
      final preference = await _preference(
        stored: {LanguageRoomPreference.prefsKey: 'es'},
        locales: const [Locale('de', 'DE')],
      );
      final resolved = await preference.resolveWithSource();
      expect(resolved.code, 'es');
      expect(resolved.source, RoomLanguageSource.explicit);
    });

    test('reports a matching device language as detected', () async {
      final preference = await _preference(
        locales: const [Locale('ja', 'JP'), Locale('fr', 'FR')],
      );
      final resolved = await preference.resolveWithSource();
      expect(resolved.code, 'fr');
      expect(resolved.source, RoomLanguageSource.detected);
    });

    test('reports English without a match as the fallback', () async {
      final preference = await _preference(
        locales: const [Locale('ja', 'JP')],
      );
      final resolved = await preference.resolveWithSource();
      expect(resolved.code, 'en');
      expect(resolved.source, RoomLanguageSource.fallback);
    });

    test('an English device is detected, not the fallback', () async {
      final preference = await _preference(
        locales: const [Locale('en', 'US')],
      );
      final resolved = await preference.resolveWithSource();
      expect(resolved.code, 'en');
      expect(resolved.source, RoomLanguageSource.detected);
    });
  });
}
