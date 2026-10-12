import 'package:characters/characters.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum UserProfileServiceErrorCode {
  nicknameTooShort,
  nicknameTooLong,
  nicknameInvalidCharacters,

  /// The user already has a nickname: it can only be chosen once.
  nicknameAlreadySet,
}

/// Thrown by [UserProfileService] operations on invalid input. The UI layer
/// maps [code] to a localized message, so no user-facing text lives here.
class UserProfileServiceException implements Exception {
  final UserProfileServiceErrorCode code;

  const UserProfileServiceException(this.code);
}

/// Reads and writes per-user public profile data (currently just the
/// nickname), stored in `userProfiles/{emailKey}` where `emailKey` is
/// [profileKey] of the user's email. Profiles are only ever fetched by
/// document id, never queried or listed.
class UserProfileService {
  UserProfileService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const int minNicknameLength = 2;
  static const int maxNicknameLength = 20;

  static final RegExp _allowedNickname =
      RegExp(r'^[\p{L}\p{N} _.\-]+$', unicode: true);
  static final RegExp _whitespaceRun = RegExp(r'\s+');

  CollectionReference<Map<String, dynamic>> get _profiles =>
      _firestore.collection('userProfiles');

  /// The document id a user's profile is stored under, so `Luca@Gmail.com`
  /// and `luca@gmail.com` share the same profile.
  static String profileKey(String email) => email.trim().toLowerCase();

  /// Trims [raw] and collapses each internal run of whitespace into a single
  /// space. This is the form that is validated and stored.
  static String normalizeNickname(String raw) =>
      raw.trim().replaceAll(_whitespaceRun, ' ');

  /// Validates the normalized form of [raw]. Returns `null` when valid; an
  /// empty value is valid here (it means "no nickname yet"), but
  /// [setNickname] refuses it.
  ///
  /// Checks run in this order and the first failure is returned: too short
  /// (< [minNicknameLength]), too long (> [maxNicknameLength]), then invalid
  /// characters (only letters, digits, space, `_`, `.` and `-` are allowed).
  /// Length is counted in user-perceived characters, so an accented letter
  /// or an emoji counts as one.
  static UserProfileServiceErrorCode? validateNickname(String raw) {
    final nickname = normalizeNickname(raw);
    if (nickname.isEmpty) return null;
    final length = nickname.characters.length;
    if (length < minNicknameLength) {
      return UserProfileServiceErrorCode.nicknameTooShort;
    }
    if (length > maxNicknameLength) {
      return UserProfileServiceErrorCode.nicknameTooLong;
    }
    if (!_allowedNickname.hasMatch(nickname)) {
      return UserProfileServiceErrorCode.nicknameInvalidCharacters;
    }
    return null;
  }

  /// The nickname of the user with [email], or `null` if none is set.
  Future<String?> getNickname(String email) async {
    final snapshot = await _profiles.doc(profileKey(email)).get();
    final nickname = snapshot.data()?['nickname'];
    if (nickname is! String || nickname.trim().isEmpty) return null;
    return nickname;
  }

  /// Sets the nickname of the user with [email] to the normalized
  /// [nickname]. A nickname can be chosen only once: throws
  /// [UserProfileServiceException] with
  /// [UserProfileServiceErrorCode.nicknameAlreadySet] if the stored one is
  /// not empty. Throws without writing anything if the nickname is invalid
  /// (see [validateNickname]) or empty.
  ///
  /// The Firestore rules enforce the same, so a concurrent write from
  /// another device fails with a permission error instead of overwriting.
  Future<void> setNickname({
    required String email,
    required String nickname,
  }) async {
    final normalized = normalizeNickname(nickname);
    final error = validateNickname(normalized);
    if (error != null) throw UserProfileServiceException(error);
    if (normalized.isEmpty) {
      throw const UserProfileServiceException(
          UserProfileServiceErrorCode.nicknameTooShort);
    }

    if (await getNickname(email) != null) {
      throw const UserProfileServiceException(
          UserProfileServiceErrorCode.nicknameAlreadySet);
    }
    await _profiles.doc(profileKey(email)).set({
      'nickname': normalized,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Nicknames for [emails], keyed by the original email strings passed in.
  /// Emails without a nickname are omitted. Duplicates are fetched once and
  /// lookups run in parallel; a lookup that fails is treated as "no
  /// nickname" rather than failing the whole call, so callers can always
  /// fall back to the masked email.
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
