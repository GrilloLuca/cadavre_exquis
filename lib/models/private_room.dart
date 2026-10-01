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
