import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/domain/models/story.dart';

void main() {
  test('wordCount splits on any whitespace', () {
    expect(wordCount(''), 0);
    expect(wordCount('  \n '), 0);
    expect(wordCount('ijhodfaxòklo'), 1);
    expect(wordCount(" C'era una\nvolta  un\tdrago "), 5);
  });
}
