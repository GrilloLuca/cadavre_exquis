import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/private_room/private_room_repository.dart';
import 'package:cadavre_exquisite/domain/models/private_room.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// Creates a new private room owned by the signed-in user.
class CreatePrivateRoomViewModel extends ChangeNotifier {
  CreatePrivateRoomViewModel({
    required PrivateRoomRepository roomRepository,
    required AuthRepository authRepository,
  })  : _rooms = roomRepository,
        _auth = authRepository {
    create = Command1<PrivateRoom?, ({String name, String password})>(_create);
  }

  final PrivateRoomRepository _rooms;
  final AuthRepository _auth;

  /// Creates the room; its value is the new room, or null if nobody is
  /// signed in. Fails with a [PrivateRoomException] with
  /// [PrivateRoomErrorCode.nameTaken] if the name is in use.
  late final Command1<PrivateRoom?, ({String name, String password})> create;

  Future<PrivateRoom?> _create(({String name, String password}) form) async {
    final email = _auth.currentEmail;
    if (email == null) return null;
    return _rooms.createRoom(
      name: form.name,
      password: form.password,
      createdBy: email,
    );
  }

  @override
  void dispose() {
    create.dispose();
    super.dispose();
  }
}
