import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/models/story.dart';
import 'package:cadavre_exquisite/services/story_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late StoryService service;

  Future<void> addStory(String id,
      {String status = 'complete',
      String language = 'it',
      String? roomId,
      bool? mature = false,
      List<int> partSeconds = const []}) {
    return firestore.collection('stories').doc(id).set({
      'status': status,
      'currentPosition': 'epilogo',
      'parts': [
        for (final (i, seconds) in partSeconds.indexed)
          {
            'position': kStoryPositions[i],
            'text': 'part $i',
            'author': 'a$i@example.com',
            'timestamp': Timestamp.fromMillisecondsSinceEpoch(seconds * 1000),
          },
      ],
      'lockedBy': null,
      'language': language,
      'roomId': roomId,
      if (mature != null) 'mature': mature,
    });
  }

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    service = StoryService(firestore: firestore);
    await addStory('it-public');
    await addStory('en-public', language: 'en');
    await addStory('it-room', roomId: 'amici');
    await addStory('other-room', roomId: 'altri');
    await addStory('it-incomplete', status: 'incomplete');
  });

  Future<List<String>> completeIds(
      {required String language, String? roomId}) async {
    final stories = await service
        .completeStoriesStream(language: language, roomId: roomId)
        .first;
    return stories.map((s) => s.id).toList();
  }

  test('public room lists only its language and no private-room stories',
      () async {
    expect(await completeIds(language: 'it'), ['it-public']);
    expect(await completeIds(language: 'en'), ['en-public']);
  });

  test('private room lists only its own stories, whatever the language',
      () async {
    expect(await completeIds(language: 'en', roomId: 'amici'), ['it-room']);
  });

  test('incomplete stream filters by status', () async {
    final stories = await service.incompleteStoriesStream(language: 'it').first;
    expect(stories.map((s) => s.id), ['it-incomplete']);
  });

  test('createStory writes an explicit null roomId for public rooms', () async {
    final story = await service.createStory(language: 'fr');
    final data =
        (await firestore.collection('stories').doc(story.id).get()).data()!;
    expect(data.containsKey('roomId'), isTrue);
    expect(data['roomId'], isNull);
    expect(await completeIds(language: 'fr'), isEmpty);
    final open = await service.incompleteStoriesStream(language: 'fr').first;
    expect(open.map((s) => s.id), [story.id]);
  });

  test('complete list includes reviewed mature and non-mature stories, '
      'excludes unreviewed', () async {
    await addStory('it-mature', mature: true);
    await addStory('it-unreviewed', mature: null);
    await addStory('room-mature', roomId: 'amici', mature: true);
    await addStory('room-unreviewed', roomId: 'amici', mature: null);

    expect(await completeIds(language: 'it'),
        unorderedEquals(['it-public', 'it-mature']));
    expect(await completeIds(language: 'it', roomId: 'amici'),
        unorderedEquals(['it-room', 'room-mature']));
  });

  test('complete list is newest completed first, ties by id', () async {
    // Ordered by the last part's timestamp, not the first one.
    await addStory('old', partSeconds: [10, 100]);
    await addStory('newest', mature: true, partSeconds: [1, 300]);
    await addStory('tie-b', partSeconds: [50, 200]);
    await addStory('tie-a', partSeconds: [60, 200]);

    // 'it-public' (from setUp) has no parts and sorts last.
    expect(await completeIds(language: 'it'),
        ['newest', 'tie-a', 'tie-b', 'old', 'it-public']);
  });

  group('Story.compareByCompletedAtDesc', () {
    Story story(String id, List<int> partSeconds) => Story(
          id: id,
          status: 'complete',
          currentPosition: 'epilogo',
          parts: [
            for (final seconds in partSeconds)
              StoryPart(
                position: 'epilogo',
                text: '',
                author: 'a@example.com',
                timestamp: Timestamp.fromMillisecondsSinceEpoch(seconds * 1000),
              ),
          ],
        );

    test('completedAt is the last part timestamp, null without parts', () {
      expect(story('x', [5, 9]).completedAt,
          Timestamp.fromMillisecondsSinceEpoch(9000));
      expect(story('x', []).completedAt, isNull);
    });

    test('sorts newest first, ties by id, partless last; input order '
        'does not matter', () {
      final expected = ['c', 'a', 'b', 'd', 'e', 'f'];
      final stories = [
        story('f', []),
        story('b', [1, 20]),
        story('d', [5]),
        story('e', []),
        story('a', [2, 20]),
        story('c', [30]),
      ];
      final sorted = [...stories]..sort(Story.compareByCompletedAtDesc);
      expect(sorted.map((s) => s.id), expected);
      final reversed = stories.reversed.toList()
        ..sort(Story.compareByCompletedAtDesc);
      expect(reversed.map((s) => s.id), expected);
    });
  });
}
