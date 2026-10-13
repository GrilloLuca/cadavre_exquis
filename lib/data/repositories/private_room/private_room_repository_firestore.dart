import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

import 'package:cadavre_exquisite/data/repositories/private_room/private_room_repository.dart';
import 'package:cadavre_exquisite/domain/models/private_room.dart';

class PrivateRoomRepositoryFirestore implements PrivateRoomRepository {
  PrivateRoomRepositoryFirestore({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _rooms =>
      _firestore.collection('privateRooms');

  /// Normalizes a room name into the id it's stored and looked up under, so
  /// "Family Night" and "family night" are the same room. Using this as the
  /// document id (rather than a query) is what lets [createRoom] check for
  /// a name collision and create the room atomically.
  static String normalizeName(String name) => name.trim().toLowerCase();

  /// Creates a new private room, salting and hashing [password] rather than
  /// storing it as plain text. Throws [PrivateRoomErrorCode.nameTaken]
  /// if a room with the same (case-insensitive) name already exists.
  @override
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
        throw const PrivateRoomException(PrivateRoomErrorCode.nameTaken);
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
  @override
  Future<PrivateRoom> joinRoom({
    required String name,
    required String password,
  }) async {
    final id = normalizeName(name);
    final snapshot = await _rooms.doc(id).get();
    if (!snapshot.exists) {
      throw const PrivateRoomException(PrivateRoomErrorCode.roomNotFound);
    }

    final data = snapshot.data()!;
    final salt = data['salt'] as String;
    final expectedHash = data['passwordHash'] as String;
    if (_hashPassword(password, salt) != expectedHash) {
      throw const PrivateRoomException(PrivateRoomErrorCode.wrongPassword);
    }

    return PrivateRoom(id: id, name: data['name'] as String);
  }
}

String _generateSalt([int length = 16]) {
  final random = Random.secure();
  return base64UrlEncode(
      List<int>.generate(length, (_) => random.nextInt(256)));
}

String _hashPassword(String password, String salt) =>
    sha256.convert(utf8.encode('$salt:$password')).toString();
