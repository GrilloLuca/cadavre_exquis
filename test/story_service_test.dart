import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/services/story_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late StoryService service;

  Future<void> addStory(String id,
      {String status = 'complete',
      String language = 'it',
      String? roomId,
      bool? mature = false}) {
    return firestore.collection('stories').doc(id).set({
      'status': status,
      'currentPosition': 'epilogo',
      'parts': [],
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
      {required String language, String? roomId, bool mature = false}) async {
    final stories = await service
        .completeStoriesStream(
            language: language, roomId: roomId, mature: mature)
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

  test('mature stories are only in the mature list, unreviewed in neither',
      () async {
    await addStory('it-mature', mature: true);
    await addStory('it-unreviewed', mature: null);

    expect(await completeIds(language: 'it'), ['it-public']);
    expect(await completeIds(language: 'it', mature: true), ['it-mature']);
  });
}
