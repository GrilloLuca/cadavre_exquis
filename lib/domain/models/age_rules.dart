/// Who counts as an adult for mature stories, given only a birth year.
abstract final class AgeRules {
  static const int adultAge = 18;
  static const int oldestBirthYear = 1900;

  /// Whether someone born in [birthYear] is certainly an adult in [now]'s
  /// year. Only the year is known, so a person who turns 18 later this year
  /// counts as a minor until next January.
  static bool isAdult(int birthYear, DateTime now) =>
      now.year - birthYear > adultAge;
}
