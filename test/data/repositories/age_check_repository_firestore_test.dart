import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/data/repositories/age_check/age_check_repository_firestore.dart';
import 'package:cadavre_exquisite/domain/models/age_rules.dart';

void main() {
  group('AgeRules.isAdult', () {
    final now = DateTime(2026, 10, 9);

    test('counts only those certainly 18 by this year', () {
      expect(AgeRules.isAdult(2007, now), isTrue);
      // Born in 2008: 18 only if the birthday has passed, so not yet.
      expect(AgeRules.isAdult(2008, now), isFalse);
      expect(AgeRules.isAdult(2015, now), isFalse);
    });
  });

  test('stores the birth year under the normalized email key', () async {
    final firestore = FakeFirebaseFirestore();
    final service = AgeCheckRepositoryFirestore(firestore: firestore);

    expect(await service.getBirthYear('Luca@Example.com'), isNull);
    await service.setBirthYear(email: 'Luca@Example.com', birthYear: 1990);

    expect(await service.getBirthYear('luca@example.com'), 1990);
    final doc =
        await firestore.collection('ageChecks').doc('luca@example.com').get();
    expect(doc.data()!['birthYear'], 1990);
  });
}
