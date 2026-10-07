import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/models/author_name.dart';

void main() {
  group('maskEmail', () {
    test('keeps the first two characters of the local part', () {
      expect(maskEmail('luca.grillo@gmail.com'), 'lu***');
    });

    test('a one-character local part keeps that character', () {
      expect(maskEmail('a@x.it'), 'a***');
    });

    test('a string without @ is treated as all local part', () {
      expect(maskEmail('lucagrillo'), 'lu***');
    });

    test('null, empty and whitespace-only return null', () {
      expect(maskEmail(null), isNull);
      expect(maskEmail(''), isNull);
      expect(maskEmail('   '), isNull);
    });

    test('an empty local part returns null', () {
      expect(maskEmail('@x.it'), isNull);
    });

    test('surrounding whitespace is ignored', () {
      expect(maskEmail('  luca@gmail.com  '), 'lu***');
    });

    test('accented and emoji first characters are grapheme-safe', () {
      expect(maskEmail('èlena@x.it'), 'èl***');
      // "e" + combining grave accent is a single grapheme.
      expect(maskEmail('e\u0300lena@x.it'), 'e\u0300l***');
      expect(maskEmail('😀😃abc@x.it'), '😀😃***');
      expect(maskEmail('👨‍👩‍👧x@x.it'), '👨‍👩‍👧x***');
    });
  });

  group('authorDisplayName', () {
    test('prefers the nickname over the email', () {
      expect(
        authorDisplayName(nickname: 'Luca', email: 'luca.grillo@gmail.com'),
        'Luca',
      );
    });

    test('trims the nickname', () {
      expect(authorDisplayName(nickname: '  Luca  ', email: 'a@x.it'), 'Luca');
    });

    test('empty or whitespace nickname falls back to the masked email', () {
      expect(
        authorDisplayName(nickname: '', email: 'luca.grillo@gmail.com'),
        'lu***',
      );
      expect(
        authorDisplayName(nickname: '   ', email: 'luca.grillo@gmail.com'),
        'lu***',
      );
      expect(authorDisplayName(email: 'luca.grillo@gmail.com'), 'lu***');
    });

    test('returns null when neither is usable', () {
      expect(authorDisplayName(), isNull);
      expect(authorDisplayName(nickname: ' ', email: '@x.it'), isNull);
    });
  });
}
