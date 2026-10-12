import 'package:cadavre_exquisite/domain/models/private_room.dart';

/// Password-protected private rooms. Room names are case-insensitive.
abstract class PrivateRoomRepository {
  /// Creates a new private room. Throws a [PrivateRoomException] with
  /// [PrivateRoomErrorCode.nameTaken] if a room with the same
  /// (case-insensitive) name already exists.
  Future<PrivateRoom> createRoom({
    required String name,
    required String password,
    required String createdBy,
  });

  /// Looks up a room by name and checks [password]. Throws a
  /// [PrivateRoomException] with [PrivateRoomErrorCode.roomNotFound] or
  /// [PrivateRoomErrorCode.wrongPassword].
  Future<PrivateRoom> joinRoom(
      {required String name, required String password});
}
