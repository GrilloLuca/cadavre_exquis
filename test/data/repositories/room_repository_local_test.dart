import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cadavre_exquisite/data/repositories/room/room_repository_local.dart';
import 'package:cadavre_exquisite/data/services/language_room_preference.dart';
import 'package:cadavre_exquisite/domain/models/private_room.dart';
import 'package:cadavre_exquisite/domain/models/story_language.dart';

import '../../../testing/fakes/repositories/fake_auth_repository.dart';

/// A preference whose storage can't be read.
class _BrokenPreference extends LanguageRoomPreference {
  _BrokenPreference() : super(deviceLocales: () => const []);

  @override
  Future<({String code, RoomLanguageSource source})> resolveWithSource() =>
      Future.error(Exception('storage'));
}

void main() {
  const room = PrivateRoom(id: 'friends', name: 'Friends');
  late FakeAuthRepository auth;

  setUp(() => auth = FakeAuthRepository(email: 'me@example.com'));

  Future<RoomRepositoryLocal> create(
      {Map<String, Object> stored = const {},
      List<Locale> locales = const [Locale('de')]}) async {
    SharedPreferences.setMockInitialValues(stored);
    return RoomRepositoryLocal(
      preference: LanguageRoomPreference(
        prefs: await SharedPreferences.getInstance(),
        deviceLocales: () => locales,
      ),
      authRepository: auth,
    );
  }

  test('loads the stored choice, or detects one', () async {
    final stored =
        await create(stored: {LanguageRoomPreference.prefsKey: 'es'});
    expect(stored.languageCode, isNull);
    await stored.load();
    expect(stored.languageCode, 'es');
    expect(stored.languageSource, RoomLanguageSource.explicit);

    final detected = await create();
    await detected.load();
    expect(detected.languageCode, 'de');
    expect(detected.languageSource, RoomLanguageSource.detected);
  });

  test('unreadable storage falls back to detection', () async {
    final rooms = RoomRepositoryLocal(
      preference: _BrokenPreference(),
      authRepository: auth,
      deviceLocales: () => const [Locale('fr')],
    );
    await rooms.load();

    expect(rooms.languageCode, 'fr');
    expect(rooms.languageSource, RoomLanguageSource.detected);
  });

  test('picking a language saves it and leaves the private room', () async {
    final rooms = await create();
    await rooms.load();
    rooms.enterPrivateRoom(room);

    await rooms.selectLanguage('it');

    expect(rooms.languageCode, 'it');
    expect(rooms.languageSource, RoomLanguageSource.explicit);
    expect(rooms.privateRoom, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LanguageRoomPreference.prefsKey), 'it');
  });

  test('signing out leaves the private room', () async {
    final rooms = await create();
    rooms.enterPrivateRoom(room);

    await auth.signOut();

    expect(rooms.privateRoom, isNull);
  });

  test('a choice made while loading is not overwritten', () async {
    final rooms = await create();
    final loading = rooms.load();
    await rooms.selectLanguage('it');
    await loading;

    expect(rooms.languageCode, 'it');
  });
}
