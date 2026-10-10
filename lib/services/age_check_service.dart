import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cadavre_exquisite/services/user_profile_service.dart';

/// Stores the birth year each user enters on the neutral age screen, in
/// `ageChecks/{emailKey}` (same key as the user profile). The answer can't
/// be changed once given, so a child can't simply retry with an older year.
class AgeCheckService {
  AgeCheckService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const int adultAge = 18;
  static const int oldestBirthYear = 1900;

  DocumentReference<Map<String, dynamic>> _doc(String email) => _firestore
      .collection('ageChecks')
      .doc(UserProfileService.profileKey(email));

  /// Whether someone born in [birthYear] is certainly an adult in [now]'s
  /// year. Only the year is known, so a person who turns 18 later this year
  /// counts as a minor until next January.
  static bool isAdult(int birthYear, DateTime now) =>
      now.year - birthYear > adultAge;

  /// The birth year the user with [email] entered, or null if never asked.
  Future<int?> getBirthYear(String email) async {
    final snapshot = await _doc(email).get();
    return snapshot.data()?['birthYear'] as int?;
  }

  /// Records [birthYear] for the user with [email]. Fails if one is already
  /// recorded (see firestore.rules).
  Future<void> setBirthYear({required String email, required int birthYear}) {
    return _doc(email).set({
      'birthYear': birthYear,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
