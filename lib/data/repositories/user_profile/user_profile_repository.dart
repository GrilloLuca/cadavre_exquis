import 'package:cadavre_exquisite/domain/models/nickname.dart';

/// Per-user public profile data (currently just the nickname), keyed by
/// email.
abstract class UserProfileRepository {
  /// The nickname of the user with [email], or `null` if none is set.
  Future<String?> getNickname(String email);

  /// Sets the nickname of the user with [email] to the normalized
  /// [nickname] (see [Nickname.normalize]). A nickname can be chosen only
  /// once. Throws a [UserProfileException] without writing anything if the
  /// nickname is invalid or empty, or with
  /// [UserProfileErrorCode.nicknameAlreadySet] if one is already stored.
  Future<void> setNickname({required String email, required String nickname});

  /// Nicknames for [emails], keyed by the original email strings passed in.
  /// Emails without a nickname are omitted; a lookup that fails counts as
  /// "no nickname" instead of failing the whole call, so callers can always
  /// fall back to the masked email.
  Future<Map<String, String>> nicknamesFor(Iterable<String> emails);
}
