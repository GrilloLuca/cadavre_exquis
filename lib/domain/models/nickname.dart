import 'package:characters/characters.dart';

enum UserProfileErrorCode {
  nicknameTooShort,
  nicknameTooLong,
  nicknameInvalidCharacters,

  /// The user already has a nickname: it can only be chosen once.
  nicknameAlreadySet,
}

/// Thrown by `UserProfileRepository` operations on invalid input. The UI
/// layer maps [code] to a localized message, so no user-facing text lives
/// here.
class UserProfileException implements Exception {
  final UserProfileErrorCode code;

  const UserProfileException(this.code);
}

/// The rules a nickname must follow, shared by the Account screen's form
/// and `UserProfileRepository.setNickname`.
abstract final class Nickname {
  static const int minLength = 2;
  static const int maxLength = 20;

  static final RegExp _allowed = RegExp(r'^[\p{L}\p{N} _.\-]+$', unicode: true);
  static final RegExp _whitespaceRun = RegExp(r'\s+');

  /// Trims [raw] and collapses each internal run of whitespace into a single
  /// space. This is the form that is validated and stored.
  static String normalize(String raw) =>
      raw.trim().replaceAll(_whitespaceRun, ' ');

  /// Validates the normalized form of [raw]. Returns `null` when valid; an
  /// empty value is valid here (it means "no nickname yet"), but
  /// `UserProfileRepository.setNickname` refuses it.
  ///
  /// Checks run in this order and the first failure is returned: too short
  /// (< [minLength]), too long (> [maxLength]), then invalid characters
  /// (only letters, digits, space, `_`, `.` and `-` are allowed). Length is
  /// counted in user-perceived characters, so an accented letter or an
  /// emoji counts as one.
  static UserProfileErrorCode? validate(String raw) {
    final nickname = normalize(raw);
    if (nickname.isEmpty) return null;
    final length = nickname.characters.length;
    if (length < minLength) return UserProfileErrorCode.nicknameTooShort;
    if (length > maxLength) return UserProfileErrorCode.nicknameTooLong;
    if (!_allowed.hasMatch(nickname)) {
      return UserProfileErrorCode.nicknameInvalidCharacters;
    }
    return null;
  }
}
