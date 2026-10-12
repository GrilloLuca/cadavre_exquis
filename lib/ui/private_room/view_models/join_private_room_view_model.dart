import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/private_room/private_room_repository.dart';
import 'package:cadavre_exquisite/domain/models/private_room.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// Joins an existing private room by name and password.
class JoinPrivateRoomViewModel extends ChangeNotifier {
  JoinPrivateRoomViewModel({required PrivateRoomRepository roomRepository})
      : _rooms = roomRepository {
    join = Command1<PrivateRoom, ({String name, String password})>(_join);
  }

  final PrivateRoomRepository _rooms;

  /// Joins the room; its value is the joined room. Fails with a
  /// [PrivateRoomException] if the room doesn't exist or the password is
  /// wrong.
  late final Command1<PrivateRoom, ({String name, String password})> join;

  Future<PrivateRoom> _join(({String name, String password}) form) =>
      _rooms.joinRoom(name: form.name, password: form.password);

  @override
  void dispose() {
    join.dispose();
    super.dispose();
  }
}
