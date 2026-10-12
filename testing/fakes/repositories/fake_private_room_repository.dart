import 'package:cadavre_exquisite/data/repositories/private_room/private_room_repository.dart';
import 'package:cadavre_exquisite/domain/models/private_room.dart';

/// In-memory [PrivateRoomRepository] for ViewModel and widget tests.
/// Passwords are kept in plain text: nothing here leaves the test.
class FakePrivateRoomRepository implements PrivateRoomRepository {
  final Map<String, ({String name, String password})> _rooms = {};

  static String _id(String name) => name.trim().toLowerCase();

  @override
  Future<PrivateRoom> createRoom({
    required String name,
    required String password,
    required String createdBy,
  }) async {
    final id = _id(name);
    if (_rooms.containsKey(id)) {
      throw const PrivateRoomException(PrivateRoomErrorCode.nameTaken);
    }
    _rooms[id] = (name: name.trim(), password: password);
    return PrivateRoom(id: id, name: name.trim());
  }

  @override
  Future<PrivateRoom> joinRoom({
    required String name,
    required String password,
  }) async {
    final id = _id(name);
    final room = _rooms[id];
    if (room == null) {
      throw const PrivateRoomException(PrivateRoomErrorCode.roomNotFound);
    }
    if (room.password != password) {
      throw const PrivateRoomException(PrivateRoomErrorCode.wrongPassword);
    }
    return PrivateRoom(id: id, name: room.name);
  }
}
