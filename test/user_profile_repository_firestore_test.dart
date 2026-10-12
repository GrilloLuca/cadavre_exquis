import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository_firestore.dart';
import 'package:cadavre_exquisite/domain/models/email_key.dart';
import 'package:cadavre_exquisite/domain/models/nickname.dart';

void main() {
  group('emailKey', () {
    test('trims and lowercases', () {
      expect(emailKey('  Luca@Gmail.COM '), 'luca@gmail.com');
    });
  });

  group('Nickname.normalize', () {
    test('trims and collapses internal whitespace runs', () {
      expect(Nickname.normalize('  Luca   \t Grillo \n'), 'Luca Grillo');
    });
  });

  group('Nickname.validate', () {
    test('empty and whitespace-only are valid (no nickname yet)', () {
      expect(Nickname.validate(''), isNull);
      expect(Nickname.validate('   '), isNull);
    });

    test('length boundaries', () {
      expect(Nickname.validate('a'), UserProfileErrorCode.nicknameTooShort);
      expect(Nickname.validate('ab'), isNull);
      expect(Nickname.validate('a' * 20), isNull);
      expect(Nickname.validate('a' * 21), UserProfileErrorCode.nicknameTooLong);
    });

    test('length is measured after normalizing', () {
      // Padded to 3 chars but normalizes to 1.
      expect(Nickname.validate(' a '), UserProfileErrorCode.nicknameTooShort);
      // 20 chars once internal whitespace is collapsed.
      expect(Nickname.validate('abcdefghi     jklmnopqrs'), isNull);
    });

    test('accented letters count as one character each', () {
      expect(Nickname.validate('è' * 20), isNull);
      expect(Nickname.validate('è' * 21), UserProfileErrorCode.nicknameTooLong);
    });

    test('decomposed accents (combining marks) are rejected', () {
      // Only precomposed letters are allowed: combining marks are not in
      // the allowed set, which also keeps "zalgo" text out.
      expect(Nickname.validate('Nicco\u0300'),
          UserProfileErrorCode.nicknameInvalidCharacters);
    });

    test('accepts letters, digits, space, underscore, dot and dash', () {
      expect(Nickname.validate('Niccolò'), isNull);
      expect(Nickname.validate('Àlex_99 .-'), isNull);
    });

    test('rejects @ and /', () {
      expect(Nickname.validate('luca@x'),
          UserProfileErrorCode.nicknameInvalidCharacters);
      expect(Nickname.validate('a/b'),
          UserProfileErrorCode.nicknameInvalidCharacters);
    });

    test('length is checked before characters', () {
      expect(Nickname.validate('@'), UserProfileErrorCode.nicknameTooShort);
      expect(Nickname.validate('@' * 21), UserProfileErrorCode.nicknameTooLong);
    });
  });

  group('UserProfileRepository with Firestore', () {
    late FakeFirebaseFirestore firestore;
    late UserProfileRepository service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = UserProfileRepositoryFirestore(firestore: firestore);
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

    test('an empty nickname throws and writes nothing', () async {
      await expectLater(
        service.setNickname(email: 'luca@gmail.com', nickname: '   '),
        throwsA(isA<UserProfileException>().having(
            (e) => e.code, 'code', UserProfileErrorCode.nicknameTooShort)),
      );
      expect((await profileDoc('luca@gmail.com')).exists, isFalse);
    });

    test('a nickname can be set only once', () async {
      await service.setNickname(email: 'luca@gmail.com', nickname: 'Luca');

      await expectLater(
        service.setNickname(email: 'Luca@Gmail.com', nickname: 'Other'),
        throwsA(isA<UserProfileException>().having(
            (e) => e.code, 'code', UserProfileErrorCode.nicknameAlreadySet)),
      );
      expect(await service.getNickname('luca@gmail.com'), 'Luca');
    });

    test('an empty stored nickname can still be set', () async {
      await firestore
          .collection('userProfiles')
          .doc('luca@gmail.com')
          .set({'nickname': ''});

      await service.setNickname(email: 'luca@gmail.com', nickname: 'Luca');
      expect(await service.getNickname('luca@gmail.com'), 'Luca');
    });

    for (final (input, code) in [
      ('a', UserProfileErrorCode.nicknameTooShort),
      ('a' * 21, UserProfileErrorCode.nicknameTooLong),
      ('luca@x', UserProfileErrorCode.nicknameInvalidCharacters),
      ('a/b', UserProfileErrorCode.nicknameInvalidCharacters),
    ]) {
      test('setNickname("$input") throws $code and writes nothing', () async {
        await service.setNickname(email: 'luca@gmail.com', nickname: 'Luca');

        await expectLater(
          service.setNickname(email: 'luca@gmail.com', nickname: input),
          throwsA(
              isA<UserProfileException>().having((e) => e.code, 'code', code)),
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
