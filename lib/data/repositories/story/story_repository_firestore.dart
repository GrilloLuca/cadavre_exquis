import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_firestore_mapping.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';

class StoryRepositoryFirestore implements StoryRepository {
  /// [now] decides whether a lock has expired; tests pass a fixed clock.
  StoryRepositoryFirestore(
      {FirebaseFirestore? firestore, DateTime Function()? now})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _now = now ?? DateTime.now;

  final FirebaseFirestore _firestore;
  final DateTime Function() _now;

  CollectionReference<Map<String, dynamic>> get _stories =>
      _firestore.collection('stories');

  /// Stories with [status] in the room identified by [language]/[roomId]:
  /// the private room [roomId] when given, otherwise the public [language]
  /// room. Public stories carry an explicit `roomId: null` so they can be
  /// matched here; the `normalizeStory` Cloud Function adds it (and the
  /// default `language`) to stories created by older app versions.
  Query<Map<String, dynamic>> _roomQuery(
    String status, {
    required String language,
    String? roomId,
  }) {
    final byStatus = _stories.where('status', isEqualTo: status);
    if (roomId != null) return byStatus.where('roomId', isEqualTo: roomId);
    return byStatus
        .where('language', isEqualTo: language)
        .where('roomId', isNull: true);
  }

  @override
  Stream<List<Story>> incompleteStoriesStream({
    required String language,
    String? roomId,
  }) {
    return _roomQuery('incomplete', language: language, roomId: roomId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(storyFromSnapshot).toList());
  }

  /// Completed stories of the room that the AI review has already judged,
  /// both `mature == false` and `mature == true` (the UI locks the latter
  /// behind the age check). Stories still waiting for their review (no
  /// `mature` field) are left out: they could be mature and there is
  /// nothing to lock yet.
  ///
  /// The `in` filter is served like an equality, so the composite indexes
  /// `(status, language, roomId, mature)` and `(status, roomId, mature)`
  /// cover it. Sorted newest completed first, see
  /// [Story.compareByCompletedAtDesc].
  @override
  Stream<List<Story>> completeStoriesStream({
    required String language,
    String? roomId,
  }) {
    return _roomQuery('complete', language: language, roomId: roomId)
        .where('mature', whereIn: [false, true])
        .snapshots()
        .map((snapshot) => snapshot.docs.map(storyFromSnapshot).toList()
          ..sort(Story.compareByCompletedAtDesc));
  }

  /// Creates an empty story and returns it, so the caller can open it
  /// straight away.
  @override
  Future<Story> createStory({required String language, String? roomId}) async {
    final docRef = await _stories.add({
      'status': 'incomplete',
      'currentPosition': kStoryPositions.first,
      'parts': [],
      'lockedBy': null,
      'lockedAt': null,
      'language': language,
      'roomId': roomId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return Story(
      id: docRef.id,
      status: 'incomplete',
      currentPosition: kStoryPositions.first,
      parts: const [],
      language: language,
      roomId: roomId,
    );
  }

  /// Exclusively locks the story for [authorEmail] so no one else can open
  /// or edit it while they're writing their part. The lock expires after
  /// [Story.lockDuration], so an abandoned turn doesn't block the story
  /// forever. Throws a [StoryException] if the story was completed,
  /// has an unexpired lock held by someone else, or the author wrote the
  /// immediately preceding part (two consecutive turns by the same author
  /// aren't allowed).
  @override
  Future<void> lockStory({
    required String storyId,
    required String authorEmail,
  }) {
    final docRef = _stories.doc(storyId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final story = storyFromSnapshot(snapshot);

      if (story.status != 'incomplete') {
        throw const StoryException(StoryErrorCode.alreadyCompleted);
      }
      if (story.wasLastWrittenBy(authorEmail)) {
        throw const StoryException(StoryErrorCode.consecutiveTurnNotAllowed);
      }
      if (story.isLockedFor(authorEmail, now: _now())) {
        throw const StoryException(StoryErrorCode.lockedByOther);
      }

      transaction.update(docRef, {
        'lockedBy': authorEmail,
        'lockedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Releases the exclusive lock held by [authorEmail], returning the story
  /// to its starting (unlocked) state. No-op if it's unlocked already or
  /// held by someone else.
  @override
  Future<void> unlockStory({
    required String storyId,
    required String authorEmail,
  }) {
    final docRef = _stories.doc(storyId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final story = storyFromSnapshot(snapshot);

      if (story.lockedBy == authorEmail) {
        transaction.update(docRef, {'lockedBy': null, 'lockedAt': null});
      }
    });
  }

  /// Appends the next part of the story inside a transaction, so two players
  /// submitting at the same time can't both write the same position. Throws
  /// a [StoryException] if the story moved on, was completed, is
  /// locked by someone else, or the author wrote the immediately preceding
  /// part (two consecutive turns by the same author aren't allowed).
  @override
  Future<void> submitPart({
    required String storyId,
    required String expectedPosition,
    required String text,
    required String authorEmail,
  }) {
    final docRef = _stories.doc(storyId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final story = storyFromSnapshot(snapshot);

      if (story.status != 'incomplete') {
        throw const StoryException(StoryErrorCode.alreadyCompleted);
      }
      if (story.currentPosition != expectedPosition) {
        throw const StoryException(StoryErrorCode.positionTaken);
      }
      if (story.isLockedFor(authorEmail, now: _now())) {
        throw const StoryException(StoryErrorCode.lockedByOther);
      }
      if (story.wasLastWrittenBy(authorEmail)) {
        throw const StoryException(StoryErrorCode.consecutiveTurnNotAllowed);
      }

      final newPart = StoryPart(
        position: expectedPosition,
        text: text,
        author: authorEmail,
        timestamp: DateTime.now(),
      );
      // The earlier parts are sent back exactly as read: firestore.rules
      // requires them unchanged, and a round trip through DateTime would
      // lose precision on web (milliseconds only).
      final storedParts = snapshot.data()?['parts'] as List<dynamic>? ?? [];
      final updatedParts = [...storedParts, storyPartToMap(newPart)];
      final next = nextPosition(expectedPosition);

      transaction.update(docRef, {
        'parts': updatedParts,
        'currentPosition': next ?? expectedPosition,
        'status': next == null ? 'complete' : 'incomplete',
        'lockedBy': null,
        'lockedAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
