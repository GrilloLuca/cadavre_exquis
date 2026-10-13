import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/domain/models/email_key.dart';
import 'package:cadavre_exquisite/domain/models/nickname.dart';

/// Reads and writes per-user public profile data (currently just the
/// nickname), stored in `userProfiles/{emailKey(email)}` (see [emailKey]). Profiles are only ever fetched by
/// document id, never queried or listed.
class UserProfileRepositoryFirestore implements UserProfileRepository {
  UserProfileRepositoryFirestore({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _profiles =>
      _firestore.collection('userProfiles');

  /// The nickname of the user with [email], or `null` if none is set.
  @override
  Future<String?> getNickname(String email) async {
    final snapshot = await _profiles.doc(emailKey(email)).get();
    final nickname = snapshot.data()?['nickname'];
    if (nickname is! String || nickname.trim().isEmpty) return null;
    return nickname;
  }

  /// Sets the nickname of the user with [email] to the normalized
  /// [nickname]. A nickname can be chosen only once: throws
  /// [UserProfileException] with
  /// [UserProfileErrorCode.nicknameAlreadySet] if the stored one is
  /// not empty. Throws without writing anything if the nickname is invalid
  /// (see [Nickname.validate]) or empty.
  ///
  /// The Firestore rules enforce the same, so a concurrent write from
  /// another device fails with a permission error instead of overwriting.
  @override
  Future<void> setNickname({
    required String email,
    required String nickname,
  }) async {
    final normalized = Nickname.normalize(nickname);
    final error = Nickname.validate(normalized);
    if (error != null) throw UserProfileException(error);
    if (normalized.isEmpty) {
      throw const UserProfileException(UserProfileErrorCode.nicknameTooShort);
    }

    if (await getNickname(email) != null) {
      throw const UserProfileException(UserProfileErrorCode.nicknameAlreadySet);
    }
    await _profiles.doc(emailKey(email)).set({
      'nickname': normalized,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Nicknames for [emails], keyed by the original email strings passed in.
  /// Emails without a nickname are omitted. Duplicates are fetched once and
  /// lookups run in parallel; a lookup that fails is treated as "no
  /// nickname" rather than failing the whole call, so callers can always
  /// fall back to the masked email.
  @override
  Future<Map<String, String>> nicknamesFor(Iterable<String> emails) async {
    final distinct = emails.toSet().toList();
    final results = await Future.wait(distinct.map((email) async {
      try {
        return await getNickname(email);
      } catch (_) {
        return null;
      }
    }));

    final nicknames = <String, String>{};
    for (var i = 0; i < distinct.length; i++) {
      final nickname = results[i];
      if (nickname != null) nicknames[distinct[i]] = nickname;
    }
    return nicknames;
  }
}
