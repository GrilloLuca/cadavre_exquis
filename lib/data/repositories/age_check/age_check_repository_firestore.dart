import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:cadavre_exquisite/data/repositories/age_check/age_check_repository.dart';
import 'package:cadavre_exquisite/domain/models/email_key.dart';

/// Stores the birth year each user enters on the neutral age screen, in
/// `ageChecks/{emailKey}` (same key as the user profile). The answer can't
/// be changed once given, so a child can't simply retry with an older year.
class AgeCheckRepositoryFirestore implements AgeCheckRepository {
  AgeCheckRepositoryFirestore({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String email) =>
      _firestore.collection('ageChecks').doc(emailKey(email));

  /// The birth year the user with [email] entered, or null if never asked.
  @override
  Future<int?> getBirthYear(String email) async {
    final snapshot = await _doc(email).get();
    return snapshot.data()?['birthYear'] as int?;
  }

  /// Records [birthYear] for the user with [email]. Fails if one is already
  /// recorded (see firestore.rules).
  @override
  Future<void> setBirthYear({required String email, required int birthYear}) {
    return _doc(email).set({
      'birthYear': birthYear,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
