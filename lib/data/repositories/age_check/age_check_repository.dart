/// The birth year each user enters on the neutral age screen. The answer
/// can't be changed once given, so a child can't simply retry with an
/// older year.
abstract class AgeCheckRepository {
  /// The birth year the user with [email] entered, or null if never asked.
  Future<int?> getBirthYear(String email);

  /// Records [birthYear] for the user with [email]. Fails if one is already
  /// recorded.
  Future<void> setBirthYear({required String email, required int birthYear});
}
