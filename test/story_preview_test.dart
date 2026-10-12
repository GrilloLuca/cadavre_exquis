import 'package:cadavre_exquisite/models/story.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Story _storyWith(String lastText) => Story(
      id: 's1',
      status: 'in_progress',
      currentPosition: 'sviluppo1',
      parts: [
        StoryPart(
          position: 'introduzione',
          text: lastText,
          author: 'a@example.com',
          timestamp: Timestamp.fromMillisecondsSinceEpoch(0),
        ),
      ],
    );

void main() {
  group('countLetters', () {
    test('ignores spaces, tabs and newlines', () {
      expect(countLetters('  ab c\n\td  '), 4);
    });

    test('counts an emoji as one letter', () {
      expect(countLetters('ciao 👋🏽'), 5);
    });
  });

  group('previewTail', () {
    test('is empty when no part has been written', () {
      final story = Story(
        id: 's1',
        status: 'in_progress',
        currentPosition: 'introduzione',
        parts: const [],
      );
      expect(story.previewTail, '');
    });

    test('returns the whole text when shorter than the limit', () {
      expect(_storyWith('  short text  ').previewTail, 'short text');
    });

    test('keeps the last 20 letters, spaces not counted', () {
      final tail =
          _storyWith('The cat sat on the mat and then it left').previewTail;
      expect(countLetters(tail), kPreviewLetterCount);
      expect(tail, 'n the mat and then it left');
    });

    test('collapses newlines into single spaces', () {
      final tail = _storyWith('aaaaaaaaaa\n\nbbbbbbbbbb').previewTail;
      expect(tail, 'aaaaaaaaaa bbbbbbbbbb');
    });
  });
}
