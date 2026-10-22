import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/domain/models/story.dart';

// Story.awaitingReview: every row of docs/PART_MODERATION_PLAN.md D3.
void main() {
  final at = DateTime.utc(2026, 10, 22);

  List<StoryPart> parts(int count) => [
        for (var i = 0; i < count; i++)
          StoryPart(
            position: kStoryPositions[i],
            text: 'part $i',
            author: 'a$i@example.com',
            timestamp: at,
          ),
      ];

  Story incomplete(int partCount,
          {Map<String, PartVerdict> partReviews = const {}, bool? mature}) =>
      Story(
        id: 's',
        status: 'incomplete',
        currentPosition: kStoryPositions[partCount],
        parts: parts(partCount),
        partReviews: partReviews,
        mature: mature,
      );

  Story complete(
          {DateTime? reviewedAt,
          bool? mature,
          Map<String, PartVerdict> partReviews = const {}}) =>
      Story(
        id: 's',
        status: 'complete',
        currentPosition: kStoryPositions.last,
        parts: parts(4),
        reviewedAt: reviewedAt,
        mature: mature,
        partReviews: partReviews,
      );

  group('an incomplete story', () {
    test('without parts has nothing to review', () {
      expect(incomplete(0).awaitingReview, isFalse);
    });

    test('awaits review while its latest part has no verdict', () {
      expect(incomplete(1).awaitingReview, isTrue);
      expect(
          incomplete(2, partReviews: {'introduzione': PartVerdict.safe})
              .awaitingReview,
          isTrue);
    });

    test('is reviewed once its latest part has a verdict, safe or mature', () {
      expect(
          incomplete(1, partReviews: {'introduzione': PartVerdict.safe})
              .awaitingReview,
          isFalse);
      expect(
          incomplete(2,
                  partReviews: {'sviluppo1': PartVerdict.mature}, mature: true)
              .awaitingReview,
          isFalse);
    });

    test('legacy, without partReviews, awaits review (until the backfill)', () {
      expect(incomplete(3).awaitingReview, isTrue);
    });

    test('a mature flag alone does not make it reviewed', () {
      expect(incomplete(1, mature: true).awaitingReview, isTrue);
    });
  });

  group('a complete story', () {
    test('awaits review until reviewedAt is set', () {
      expect(complete().awaitingReview, isTrue);
      expect(complete(reviewedAt: at).awaitingReview, isFalse);
    });

    test('flagged by a part before completion still awaits its review', () {
      final flagged = complete(mature: true, partReviews: {
        for (final p in kStoryPositions.take(3)) p: PartVerdict.mature
      });

      expect(flagged.awaitingReview, isTrue);
    });

    test(
        'legacy, reviewed before reviewedAt existed, awaits review until the '
        'backfill marks it', () {
      expect(complete(mature: false).awaitingReview, isTrue);
      expect(complete(mature: false, reviewedAt: at).awaitingReview, isFalse);
    });
  });
}
