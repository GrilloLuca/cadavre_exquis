import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/domain/models/email_key.dart';
import 'package:cadavre_exquisite/domain/models/nickname.dart';

/// In-memory [UserProfileRepository] for ViewModel and widget tests.
/// [nicknames] is keyed by email; [failWith] makes every call throw.
class FakeUserProfileRepository implements UserProfileRepository {
  FakeUserProfileRepository({Map<String, String> nicknames = const {}})
      : _nicknames = {
          for (final entry in nicknames.entries)
            emailKey(entry.key): entry.value,
        };

  final Map<String, String> _nicknames;

  /// When set, every call throws it.
  Object? failWith;

  void _checkFailure() {
    final failure = failWith;
    if (failure != null) throw failure;
  }

  @override
  Future<String?> getNickname(String email) async {
    _checkFailure();
    return _nicknames[emailKey(email)];
  }

  @override
  Future<void> setNickname({
    required String email,
    required String nickname,
  }) async {
    _checkFailure();
    final normalized = Nickname.normalize(nickname);
    final error = Nickname.validate(normalized);
    if (error != null) throw UserProfileException(error);
    if (normalized.isEmpty) {
      throw const UserProfileException(UserProfileErrorCode.nicknameTooShort);
    }
    if (_nicknames.containsKey(emailKey(email))) {
      throw const UserProfileException(UserProfileErrorCode.nicknameAlreadySet);
    }
    _nicknames[emailKey(email)] = normalized;
  }

  @override
  Future<Map<String, String>> nicknamesFor(Iterable<String> emails) async {
    if (failWith != null) return {};
    return {
      for (final email in emails)
        if (_nicknames[emailKey(email)] case final nickname?) email: nickname,
    };
  }
}
