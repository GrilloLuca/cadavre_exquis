/// A private, password-protected room created by a player so they and a
/// closed group of friends can play together outside the public language
/// rooms. [id] is the room name normalized (trimmed, lower-cased) into the
/// Firestore document id, which doubles as the join key and the value
/// stories in the room are tagged with.
class PrivateRoom {
  final String id;
  final String name;

  const PrivateRoom({required this.id, required this.name});
}

enum PrivateRoomErrorCode { nameTaken, roomNotFound, wrongPassword }

/// Thrown by `PrivateRoomRepository` operations. The UI layer maps [code] to
/// a localized message, so no user-facing text lives here. [roomNotFound]
/// and [wrongPassword] are deliberately kept distinct only at this layer:
/// the UI should show the same generic message for both, so a join attempt
/// can't be used to probe whether a room name exists.
class PrivateRoomException implements Exception {
  final PrivateRoomErrorCode code;

  const PrivateRoomException(this.code);
}
