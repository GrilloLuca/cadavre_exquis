import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

import 'package:cadavre_exquisite/models/private_room.dart';

enum PrivateRoomServiceErrorCode { nameTaken, roomNotFound, wrongPassword }

/// Thrown by [PrivateRoomService] operations. The UI layer maps [code] to a
/// localized message, so no user-facing text lives here. [roomNotFound] and
/// [wrongPassword] are deliberately kept distinct only at this layer: the UI
/// should show the same generic message for both, so a join attempt can't be
/// used to probe whether a room name exists.
class PrivateRoomServiceException implements Exception {
  final PrivateRoomServiceErrorCode code;

  const PrivateRoomServiceException(this.code);
}

class PrivateRoomService {
  final _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _rooms =>
      _firestore.collection('privateRooms');

  /// Normalizes a room name into the id it's stored and looked up under, so
  /// "Family Night" and "family night" are the same room. Using this as the
  /// document id (rather than a query) is what lets [createRoom] check for
  /// a name collision and create the room atomically.
  static String normalizeName(String name) => name.trim().toLowerCase();

  /// Creates a new private room, salting and hashing [password] rather than
  /// storing it as plain text. Throws [PrivateRoomServiceErrorCode.nameTaken]
  /// if a room with the same (case-insensitive) name already exists.
  Future<PrivateRoom> createRoom({
    required String name,
    required String password,
    required String createdBy,
  }) async {
    final trimmedName = name.trim();
    final id = normalizeName(name);
    final docRef = _rooms.doc(id);
    final salt = _generateSalt();
    final passwordHash = _hashPassword(password, salt);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (snapshot.exists) {
        throw const PrivateRoomServiceException(
            PrivateRoomServiceErrorCode.nameTaken);
      }
      transaction.set(docRef, {
        'name': trimmedName,
        'passwordHash': passwordHash,
        'salt': salt,
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    return PrivateRoom(id: id, name: trimmedName);
  }

  /// Looks up a room by name and checks [password] against its stored hash.
  Future<PrivateRoom> joinRoom({
    required String name,
    required String password,
  }) async {
    final id = normalizeName(name);
    final snapshot = await _rooms.doc(id).get();
    if (!snapshot.exists) {
      throw const PrivateRoomServiceException(
          PrivateRoomServiceErrorCode.roomNotFound);
    }

    final data = snapshot.data()!;
    final salt = data['salt'] as String;
    final expectedHash = data['passwordHash'] as String;
    if (_hashPassword(password, salt) != expectedHash) {
      throw const PrivateRoomServiceException(
          PrivateRoomServiceErrorCode.wrongPassword);
    }

    return PrivateRoom(id: id, name: data['name'] as String);
  }
}

String _generateSalt([int length = 16]) {
  final random = Random.secure();
  return base64UrlEncode(List<int>.generate(length, (_) => random.nextInt(256)));
}

String _hashPassword(String password, String salt) =>
    sha256.convert(utf8.encode('$salt:$password')).toString();
