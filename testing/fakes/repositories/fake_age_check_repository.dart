import 'package:cadavre_exquisite/data/repositories/age_check/age_check_repository.dart';
import 'package:cadavre_exquisite/domain/models/email_key.dart';

/// In-memory [AgeCheckRepository] for ViewModel and widget tests. Like the
/// Firestore rules, a birth year can be set only once.
class FakeAgeCheckRepository implements AgeCheckRepository {
  FakeAgeCheckRepository({Map<String, int> birthYears = const {}})
      : _birthYears = {
          for (final entry in birthYears.entries)
            emailKey(entry.key): entry.value,
        };

  final Map<String, int> _birthYears;

  @override
  Future<int?> getBirthYear(String email) async => _birthYears[emailKey(email)];

  @override
  Future<void> setBirthYear({
    required String email,
    required int birthYear,
  }) async {
    if (_birthYears.containsKey(emailKey(email))) {
      throw StateError('Birth year already set for $email');
    }
    _birthYears[emailKey(email)] = birthYear;
  }
}
