import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/data/repositories/story/story_firestore_mapping.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/models/story_language.dart';

void main() {
  final at = DateTime.utc(2026, 10, 12, 10, 30);

  test('a part survives a round trip, stored as a Timestamp', () {
    final part = StoryPart(
        position: 'sviluppo1', text: 'hello', author: 'a@b.it', timestamp: at);

    final map = storyPartToMap(part);
    final back = storyPartFromMap(map);

    expect(map['timestamp'], Timestamp.fromDate(at));
    expect(back.timestamp.isAtSameMomentAs(at), isTrue);
    expect((back.position, back.text, back.author),
        ('sviluppo1', 'hello', 'a@b.it'));
  });

  test('a stored story maps to the domain model with DateTime fields',
      () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('stories').doc('s1').set({
      'status': 'incomplete',
      'currentPosition': 'sviluppo1',
      'parts': [
        storyPartToMap(StoryPart(
            position: 'introduzione',
            text: 'x',
            author: 'a@b.it',
            timestamp: at)),
      ],
      'lockedBy': 'c@d.it',
      'lockedAt': Timestamp.fromDate(at),
      'roomId': null,
    });

    final story = storyFromSnapshot(
        await firestore.collection('stories').doc('s1').get());

    expect(story.id, 's1');
    expect(story.lockedAt!.isAtSameMomentAs(at), isTrue);
    expect(story.parts.single.timestamp.isAtSameMomentAs(at), isTrue);
    // Legacy stories without `language` are Italian.
    expect(story.language, kDefaultStoryLanguage);
    // Stories without `keywords` (never extracted, or legacy) have none.
    expect(story.keywords, isEmpty);
  });

  group('keywords', () {
    Future<Story> storyWith(Object? keywords) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('stories').doc('s1').set({
        'status': 'incomplete',
        'currentPosition': 'sviluppo1',
        'parts': [],
        'keywords': keywords,
      });
      return storyFromSnapshot(
          await firestore.collection('stories').doc('s1').get());
    }

    test('a valid list is read as is', () async {
      final story = await storyWith(['drago', 'faro', 'tempesta']);

      expect(story.keywords, ['drago', 'faro', 'tempesta']);
    });

    test('an empty list means no keywords', () async {
      expect((await storyWith([])).keywords, isEmpty);
    });

    test('entries that are not strings are dropped', () async {
      final story = await storyWith([1, 'drago', null, true, 'faro', {}]);

      expect(story.keywords, ['drago', 'faro']);
    });

    test('at most 4 are kept', () async {
      final story = await storyWith(['a', 'b', 'c', 'd', 'e']);

      expect(story.keywords, ['a', 'b', 'c', 'd']);
    });

    test('a field that is not a list gives none', () async {
      expect((await storyWith(null)).keywords, isEmpty);
      expect((await storyWith('drago, faro')).keywords, isEmpty);
      expect((await storyWith({'0': 'drago'})).keywords, isEmpty);
    });
  });
}
