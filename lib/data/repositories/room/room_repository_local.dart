import 'package:flutter/widgets.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/room/room_repository.dart';
import 'package:cadavre_exquisite/data/services/language_room_preference.dart';
import 'package:cadavre_exquisite/domain/models/private_room.dart';
import 'package:cadavre_exquisite/domain/models/story_language.dart';

/// [RoomRepository] keeping the language choice on the device (through
/// [LanguageRoomPreference]) and the private room in memory.
class RoomRepositoryLocal extends RoomRepository {
  /// Leaves the private room when [authRepository] reports a sign-out.
  /// [deviceLocales] is used when the stored choice can't be read.
  RoomRepositoryLocal({
    required LanguageRoomPreference preference,
    required AuthRepository authRepository,
    List<Locale> Function()? deviceLocales,
  })  : _preference = preference,
        _auth = authRepository,
        _deviceLocales = deviceLocales ??
            (() => WidgetsBinding.instance.platformDispatcher.locales) {
    _auth.addListener(_onAuthChanged);
  }

  final LanguageRoomPreference _preference;
  final AuthRepository _auth;
  final List<Locale> Function() _deviceLocales;

  String? _languageCode;
  RoomLanguageSource _languageSource = RoomLanguageSource.explicit;
  PrivateRoom? _privateRoom;
  Future<void>? _loading;

  @override
  String? get languageCode => _languageCode;

  @override
  RoomLanguageSource get languageSource => _languageSource;

  @override
  PrivateRoom? get privateRoom => _privateRoom;

  @override
  Future<void> load() => _loading ??= _resolve();

  Future<void> _resolve() async {
    ({String code, RoomLanguageSource source}) resolved;
    try {
      resolved = await _preference.resolveWithSource();
    } catch (_) {
      // Unreadable storage: behave as if nothing were stored.
      resolved = detectRoomLanguageWithSource(_deviceLocales());
    }
    // An explicit choice made while resolving wins.
    if (_languageCode != null) return;
    _languageCode = resolved.code;
    _languageSource = resolved.source;
    notifyListeners();
  }

  @override
  Future<void> selectLanguage(String code) async {
    _languageCode = code;
    _languageSource = RoomLanguageSource.explicit;
    _privateRoom = null;
    notifyListeners();
    try {
      await _preference.saveExplicit(code);
    } catch (_) {
      // Keep the choice for this session only.
    }
  }

  @override
  void enterPrivateRoom(PrivateRoom room) {
    _privateRoom = room;
    notifyListeners();
  }

  @override
  void leavePrivateRoom() {
    if (_privateRoom == null) return;
    _privateRoom = null;
    notifyListeners();
  }

  void _onAuthChanged() {
    if (!_auth.isAuthenticated) leavePrivateRoom();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
