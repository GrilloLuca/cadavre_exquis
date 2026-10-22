import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository_firestore.dart';

const _holder = 'holder@example.com';
const _other = 'other@example.com';

final _lockedAt = DateTime.utc(2026, 10, 12, 10);

Story _story({String? lockedBy = _holder, DateTime? lockedAt}) => Story(
      id: 's',
      status: 'incomplete',
      currentPosition: kStoryPositions.first,
      parts: const [],
      lockedBy: lockedBy,
      lockedAt: lockedAt,
    );

void main() {
  group('Story lock expiry', () {
    test('a fresh lock blocks others but not its holder', () {
      final story = _story(lockedAt: _lockedAt);
      final now = _lockedAt.add(const Duration(minutes: 59));

      expect(story.isLockExpired(now: now), isFalse);
      expect(story.isLockedFor(_other, now: now), isTrue);
      expect(story.isLockedFor(_holder, now: now), isFalse);
    });

    test('a lock expires after exactly one hour', () {
      final story = _story(lockedAt: _lockedAt);
      final now = _lockedAt.add(Story.lockDuration);

      expect(story.isLockExpired(now: now), isTrue);
      expect(story.isLockedFor(_other, now: now), isFalse);
    });

    test('a lock without lockedAt (older app versions) is expired', () {
      final story = _story();

      expect(story.isLockExpired(), isTrue);
      expect(story.isLockedFor(_other), isFalse);
    });

    test('an unlocked story is never locked', () {
      expect(_story(lockedBy: null).isLockedFor(_other), isFalse);
    });
  });

  group('StoryRepository locks', () {
    late FakeFirebaseFirestore firestore;
    late DateTime now;
    late StoryRepository service;

    DocumentReference<Map<String, dynamic>> doc() =>
        firestore.collection('stories').doc('s');

    Future<Map<String, dynamic>> data() async => (await doc().get()).data()!;

    Future<void> seed({String? lockedBy, DateTime? lockedAt}) => doc().set({
          'status': 'incomplete',
          'currentPosition': kStoryPositions.first,
          'parts': [],
          'lockedBy': lockedBy,
          'lockedAt': lockedAt == null ? null : Timestamp.fromDate(lockedAt),
          'language': 'it',
          'roomId': null,
        });

    Matcher throwsLockedByOther() => throwsA(isA<StoryException>()
        .having((e) => e.code, 'code', StoryErrorCode.lockedByOther));

    setUp(() {
      firestore = FakeFirebaseFirestore();
      now = _lockedAt;
      service = StoryRepositoryFirestore(firestore: firestore, now: () => now);
    });

    test('lockStory records who locked it and when', () async {
      await seed();

      await service.lockStory(storyId: 's', authorEmail: _holder);

      final stored = await data();
      expect(stored['lockedBy'], _holder);
      expect(stored['lockedAt'], isA<Timestamp>());
    });

    test('a fresh lock held by someone else is refused', () async {
      await seed(lockedBy: _holder, lockedAt: _lockedAt);
      now = _lockedAt.add(const Duration(minutes: 30));

      await expectLater(
        service.lockStory(storyId: 's', authorEmail: _other),
        throwsLockedByOther(),
      );
      await expectLater(
        service.submitPart(
          storyId: 's',
          expectedPosition: kStoryPositions.first,
          text: 'hello',
          authorEmail: _other,
        ),
        throwsLockedByOther(),
      );
      expect((await data())['lockedBy'], _holder);
    });

    test('an expired lock can be taken by someone else', () async {
      await seed(lockedBy: _holder, lockedAt: _lockedAt);
      now = _lockedAt.add(const Duration(hours: 1, minutes: 1));

      await service.lockStory(storyId: 's', authorEmail: _other);

      expect((await data())['lockedBy'], _other);
    });

    test('a lock without lockedAt can be taken by someone else', () async {
      await seed(lockedBy: _holder);

      await service.lockStory(storyId: 's', authorEmail: _other);

      expect((await data())['lockedBy'], _other);
    });

    test('a part can be submitted over an expired lock, clearing it', () async {
      await seed(lockedBy: _holder, lockedAt: _lockedAt);
      now = _lockedAt.add(const Duration(hours: 2));

      await service.submitPart(
        storyId: 's',
        expectedPosition: kStoryPositions.first,
        text: 'hello',
        authorEmail: _other,
      );

      final stored = await data();
      expect(stored['lockedBy'], isNull);
      expect(stored['lockedAt'], isNull);
      expect((stored['parts'] as List<dynamic>).length, 1);
    });

    test('unlockStory clears both lock fields', () async {
      await seed(lockedBy: _holder, lockedAt: _lockedAt);

      await service.unlockStory(storyId: 's', authorEmail: _holder);

      final stored = await data();
      expect(stored['lockedBy'], isNull);
      expect(stored['lockedAt'], isNull);
    });

    group('a story whose last part awaits review', () {
      Matcher throwsUnderReview() => throwsA(isA<StoryException>()
          .having((e) => e.code, 'code', StoryErrorCode.underReview));

      Future<void> seedWithPart({Object? partReviews}) => doc().set({
            'status': 'incomplete',
            'currentPosition': kStoryPositions[1],
            'parts': [
              {
                'position': kStoryPositions.first,
                'text': 'first',
                'author': _holder,
                'timestamp': Timestamp.fromDate(_lockedAt),
              },
            ],
            'lockedBy': null,
            'lockedAt': null,
            'language': 'it',
            'roomId': null,
            if (partReviews != null) 'partReviews': partReviews,
          });

      Future<void> submit() => service.submitPart(
            storyId: 's',
            expectedPosition: kStoryPositions[1],
            text: 'second',
            authorEmail: _other,
          );

      test('refuses lock and submit, writing nothing', () async {
        // Legacy (no field), no entry yet, and an unknown value.
        for (final reviews in [
          null,
          <String, Object>{},
          {kStoryPositions.first: 'pending'},
        ]) {
          await seedWithPart(partReviews: reviews);

          await expectLater(
            service.lockStory(storyId: 's', authorEmail: _other),
            throwsUnderReview(),
            reason: '$reviews',
          );
          await expectLater(submit(), throwsUnderReview(), reason: '$reviews');
          final stored = await data();
          expect(stored['lockedBy'], isNull);
          expect(stored['parts'] as List<dynamic>, hasLength(1));
        }
      });

      test('allows lock and submit once the part has a verdict', () async {
        for (final verdict in ['safe', 'mature']) {
          await seedWithPart(partReviews: {kStoryPositions.first: verdict});

          await service.lockStory(storyId: 's', authorEmail: _other);
          expect((await data())['lockedBy'], _other, reason: verdict);
          await submit();
          expect((await data())['parts'] as List<dynamic>, hasLength(2));
        }
      });

      test('the holder can still release a lock', () async {
        await seedWithPart();
        await doc().update({
          'lockedBy': _holder,
          'lockedAt': Timestamp.fromDate(_lockedAt),
        });

        await service.unlockStory(storyId: 's', authorEmail: _holder);

        expect((await data())['lockedBy'], isNull);
      });
    });

    test('createStory starts with no lock', () async {
      final story = await service.createStory(language: 'it');

      final stored =
          (await firestore.collection('stories').doc(story.id).get()).data()!;
      expect(stored['lockedBy'], isNull);
      expect(stored.containsKey('lockedAt'), isTrue);
      expect(stored['lockedAt'], isNull);
    });
  });
}
