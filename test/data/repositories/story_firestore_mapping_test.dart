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
    // Legacy stories have no verdicts and no review date.
    expect(story.partReviews, isEmpty);
    expect(story.reviewedAt, isNull);
    expect(story.mature, isNull);
  });

  group('review fields', () {
    Future<Story> storyWith(Map<String, Object?> fields) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('stories').doc('s1').set({
        'status': 'complete',
        'currentPosition': 'epilogo',
        'parts': [],
        ...fields,
      });
      return storyFromSnapshot(
          await firestore.collection('stories').doc('s1').get());
    }

    test('verdicts are read by part position', () async {
      final story = await storyWith({
        'partReviews': {'introduzione': 'safe', 'sviluppo1': 'mature'},
      });

      expect(story.partReviews, {
        'introduzione': PartVerdict.safe,
        'sviluppo1': PartVerdict.mature,
      });
    });

    test('unknown verdict values are dropped', () async {
      final story = await storyWith({
        'partReviews': {
          'introduzione': 'safe',
          'sviluppo1': 'MATURE',
          'sviluppo2': true,
          'epilogo': null,
        },
      });

      expect(story.partReviews, {'introduzione': PartVerdict.safe});
    });

    test('a partReviews field that is not a map gives none', () async {
      for (final field in [
        null,
        'safe',
        ['safe'],
        3
      ]) {
        expect((await storyWith({'partReviews': field})).partReviews, isEmpty,
            reason: '$field');
      }
    });

    test('reviewedAt is read as a DateTime; anything else is null', () async {
      final story = await storyWith({'reviewedAt': Timestamp.fromDate(at)});
      expect(story.reviewedAt!.isAtSameMomentAs(at), isTrue);

      for (final field in [null, 'yesterday', 12, true]) {
        expect((await storyWith({'reviewedAt': field})).reviewedAt, isNull,
            reason: '$field');
      }
    });

    test('a mature field that is not a boolean is null', () async {
      expect((await storyWith({'mature': true})).mature, isTrue);
      expect((await storyWith({'mature': 'yes'})).mature, isNull);
    });
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
