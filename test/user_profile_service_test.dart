import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

import 'package:cadavre_exquisite/services/user_profile_service.dart';

void main() {
  group('UserProfileService.profileKey', () {
    test('trims and lowercases', () {
      expect(
          UserProfileService.profileKey('  Luca@Gmail.COM '), 'luca@gmail.com');
    });
  });

  group('UserProfileService.normalizeNickname', () {
    test('trims and collapses internal whitespace runs', () {
      expect(UserProfileService.normalizeNickname('  Luca   \t Grillo \n'),
          'Luca Grillo');
    });
  });

  group('UserProfileService.validateNickname', () {
    test('empty and whitespace-only are valid (clear)', () {
      expect(UserProfileService.validateNickname(''), isNull);
      expect(UserProfileService.validateNickname('   '), isNull);
    });

    test('length boundaries', () {
      expect(UserProfileService.validateNickname('a'),
          UserProfileServiceErrorCode.nicknameTooShort);
      expect(UserProfileService.validateNickname('ab'), isNull);
      expect(UserProfileService.validateNickname('a' * 20), isNull);
      expect(UserProfileService.validateNickname('a' * 21),
          UserProfileServiceErrorCode.nicknameTooLong);
    });

    test('length is measured after normalizing', () {
      // Padded to 3 chars but normalizes to 1.
      expect(UserProfileService.validateNickname(' a '),
          UserProfileServiceErrorCode.nicknameTooShort);
      // 20 chars once internal whitespace is collapsed.
      expect(UserProfileService.validateNickname('abcdefghi     jklmnopqrs'),
          isNull);
    });

    test('accented letters count as one character each', () {
      expect(UserProfileService.validateNickname('è' * 20), isNull);
      expect(UserProfileService.validateNickname('è' * 21),
          UserProfileServiceErrorCode.nicknameTooLong);
    });

    test('decomposed accents (combining marks) are rejected', () {
      // Only precomposed letters are allowed: combining marks are not in
      // the allowed set, which also keeps "zalgo" text out.
      expect(UserProfileService.validateNickname('Nicco\u0300'),
          UserProfileServiceErrorCode.nicknameInvalidCharacters);
    });

    test('accepts letters, digits, space, underscore, dot and dash', () {
      expect(UserProfileService.validateNickname('Niccolò'), isNull);
      expect(UserProfileService.validateNickname('Àlex_99 .-'), isNull);
    });

    test('rejects @ and /', () {
      expect(UserProfileService.validateNickname('luca@x'),
          UserProfileServiceErrorCode.nicknameInvalidCharacters);
      expect(UserProfileService.validateNickname('a/b'),
          UserProfileServiceErrorCode.nicknameInvalidCharacters);
    });

    test('length is checked before characters', () {
      expect(UserProfileService.validateNickname('@'),
          UserProfileServiceErrorCode.nicknameTooShort);
      expect(UserProfileService.validateNickname('@' * 21),
          UserProfileServiceErrorCode.nicknameTooLong);
    });
  });

  group('UserProfileService with Firestore', () {
    late FakeFirebaseFirestore firestore;
    late UserProfileService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = UserProfileService(firestore: firestore);
    });

    Future<DocumentSnapshot<Map<String, dynamic>>> profileDoc(String id) =>
        firestore.collection('userProfiles').doc(id).get();

    test('getNickname returns null when unset', () async {
      expect(await service.getNickname('luca@gmail.com'), isNull);
    });

    test('set/get round-trip stores the normalized nickname', () async {
      await service.setNickname(
          email: 'luca@gmail.com', nickname: '  Luca   Grillo ');

      expect(await service.getNickname('luca@gmail.com'), 'Luca Grillo');
      final doc = await profileDoc('luca@gmail.com');
      expect(doc.data()!['nickname'], 'Luca Grillo');
      expect(doc.data()!.containsKey('updatedAt'), isTrue);
    });

    test('mixed-case email maps to the same document', () async {
      await service.setNickname(email: ' Luca@Gmail.com ', nickname: 'Luca');

      expect((await profileDoc('luca@gmail.com')).exists, isTrue);
      expect(await service.getNickname('LUCA@gmail.com'), 'Luca');
    });

    test('an empty nickname deletes the document', () async {
      await service.setNickname(email: 'luca@gmail.com', nickname: 'Luca');
      await service.setNickname(email: 'luca@gmail.com', nickname: '   ');

      expect((await profileDoc('luca@gmail.com')).exists, isFalse);
      expect(await service.getNickname('luca@gmail.com'), isNull);
    });

    test('deleteProfile removes the profile of a mixed-case email', () async {
      await service.setNickname(email: 'luca@gmail.com', nickname: 'Luca');
      await service.deleteProfile(' Luca@Gmail.com ');

      expect((await profileDoc('luca@gmail.com')).exists, isFalse);
    });

    test('clearing a nickname that was never set is a no-op', () async {
      await service.setNickname(email: 'luca@gmail.com', nickname: '');
      expect((await profileDoc('luca@gmail.com')).exists, isFalse);
    });

    for (final (input, code) in [
      ('a', UserProfileServiceErrorCode.nicknameTooShort),
      ('a' * 21, UserProfileServiceErrorCode.nicknameTooLong),
      ('luca@x', UserProfileServiceErrorCode.nicknameInvalidCharacters),
      ('a/b', UserProfileServiceErrorCode.nicknameInvalidCharacters),
    ]) {
      test('setNickname("$input") throws $code and writes nothing', () async {
        await service.setNickname(email: 'luca@gmail.com', nickname: 'Luca');

        await expectLater(
          service.setNickname(email: 'luca@gmail.com', nickname: input),
          throwsA(isA<UserProfileServiceException>()
              .having((e) => e.code, 'code', code)),
        );
        expect(await service.getNickname('luca@gmail.com'), 'Luca');
      });
    }

    test('nicknamesFor handles duplicates and missing profiles', () async {
      await service.setNickname(email: 'luca@gmail.com', nickname: 'Luca');
      await service.setNickname(email: 'anna@x.it', nickname: 'Anna');

      final result = await service.nicknamesFor([
        'luca@gmail.com',
        'Luca@Gmail.com',
        'luca@gmail.com',
        'anna@x.it',
        'nobody@x.it',
      ]);

      expect(result, {
        'luca@gmail.com': 'Luca',
        'Luca@Gmail.com': 'Luca',
        'anna@x.it': 'Anna',
      });
    });

    test('nicknamesFor with no emails returns an empty map', () async {
      expect(await service.nicknamesFor(const []), isEmpty);
    });

    test('nicknamesFor omits an email whose lookup fails', () async {
      await service.setNickname(email: 'luca@gmail.com', nickname: 'Luca');
      await service.setNickname(email: 'anna@x.it', nickname: 'Anna');
      final failing = firestore.collection('userProfiles').doc('anna@x.it');
      whenCalling(Invocation.method(#get, null))
          .on(failing)
          .thenThrow(FirebaseException(plugin: 'cloud_firestore'));

      final result =
          await service.nicknamesFor(['luca@gmail.com', 'anna@x.it']);

      expect(result, {'luca@gmail.com': 'Luca'});
    });
  });
}
