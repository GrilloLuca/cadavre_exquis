import 'dart:async';

import 'package:cadavre_exquisite/data/repositories/room/room_repository.dart';
import 'package:cadavre_exquisite/domain/models/private_room.dart';
import 'package:cadavre_exquisite/domain/models/story_language.dart';

/// In-memory [RoomRepository] for ViewModel and widget tests. Starts in
/// [languageCode] (already resolved), or, with [pendingLoad], resolves to
/// it only when that future completes. Records every change in [calls].
class FakeRoomRepository extends RoomRepository {
  FakeRoomRepository({
    String languageCode = 'it',
    RoomLanguageSource languageSource = RoomLanguageSource.explicit,
    PrivateRoom? privateRoom,
    Future<void>? pendingLoad,
  })  : _resolvedCode = languageCode,
        _languageSource = languageSource,
        _privateRoom = privateRoom,
        _pendingLoad = pendingLoad,
        _languageCode = pendingLoad == null ? languageCode : null;

  final String _resolvedCode;
  final Future<void>? _pendingLoad;
  String? _languageCode;
  RoomLanguageSource _languageSource;
  PrivateRoom? _privateRoom;

  /// What the user did: `'language:<code>'`, `'enter:<room id>'`, `'leave'`.
  final List<String> calls = [];

  @override
  String? get languageCode => _languageCode;

  @override
  RoomLanguageSource get languageSource => _languageSource;

  @override
  PrivateRoom? get privateRoom => _privateRoom;

  @override
  Future<void> load() async {
    final pending = _pendingLoad;
    if (pending == null || _languageCode != null) return;
    await pending;
    _languageCode ??= _resolvedCode;
    notifyListeners();
  }

  @override
  Future<void> selectLanguage(String code) async {
    calls.add('language:$code');
    _languageCode = code;
    _languageSource = RoomLanguageSource.explicit;
    _privateRoom = null;
    notifyListeners();
  }

  @override
  void enterPrivateRoom(PrivateRoom room) {
    calls.add('enter:${room.id}');
    _privateRoom = room;
    notifyListeners();
  }

  @override
  void leavePrivateRoom() {
    calls.add('leave');
    _privateRoom = null;
    notifyListeners();
  }
}
