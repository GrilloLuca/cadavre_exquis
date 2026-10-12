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
  });
}
