import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cadavre_exquisite/models/story.dart';

enum StoryServiceErrorCode {
  alreadyCompleted,
  positionTaken,
  lockedByOther,
  consecutiveTurnNotAllowed,
}

/// Thrown by [StoryService] operations on invalid story state. The UI layer
/// maps [code] to a localized message, so no user-facing text lives here.
class StoryServiceException implements Exception {
  final StoryServiceErrorCode code;

  const StoryServiceException(this.code);
}

class StoryService {
  StoryService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

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

  Stream<List<Story>> incompleteStoriesStream({
    required String language,
    String? roomId,
  }) {
    return _roomQuery('incomplete', language: language, roomId: roomId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Story.fromSnapshot).toList());
  }

  Stream<List<Story>> completeStoriesStream({
    required String language,
    String? roomId,
  }) {
    return _roomQuery('complete', language: language, roomId: roomId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Story.fromSnapshot).toList());
  }

  /// Creates an empty story and returns it, so the caller can open it
  /// straight away.
  Future<Story> createStory({required String language, String? roomId}) async {
    final docRef = await _stories.add({
      'status': 'incomplete',
      'currentPosition': kStoryPositions.first,
      'parts': [],
      'lockedBy': null,
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
  /// or edit it while they're writing their part. Throws a
  /// [StoryServiceException] if the story was completed, already has a lock
  /// held by someone else, or the author wrote the immediately preceding
  /// part (two consecutive turns by the same author aren't allowed).
  Future<void> lockStory({
    required String storyId,
    required String authorEmail,
  }) {
    final docRef = _stories.doc(storyId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final story = Story.fromSnapshot(snapshot);

      if (story.status != 'incomplete') {
        throw const StoryServiceException(
            StoryServiceErrorCode.alreadyCompleted);
      }
      if (story.wasLastWrittenBy(authorEmail)) {
        throw const StoryServiceException(
            StoryServiceErrorCode.consecutiveTurnNotAllowed);
      }
      if (story.isLockedFor(authorEmail)) {
        throw const StoryServiceException(StoryServiceErrorCode.lockedByOther);
      }

      transaction.update(docRef, {'lockedBy': authorEmail});
    });
  }

  /// Releases the exclusive lock held by [authorEmail], returning the story
  /// to its starting (unlocked) state. No-op if it's unlocked already or
  /// held by someone else.
  Future<void> unlockStory({
    required String storyId,
    required String authorEmail,
  }) {
    final docRef = _stories.doc(storyId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final story = Story.fromSnapshot(snapshot);

      if (story.lockedBy == authorEmail) {
        transaction.update(docRef, {'lockedBy': null});
      }
    });
  }

  /// Appends the next part of the story inside a transaction, so two players
  /// submitting at the same time can't both write the same position. Throws
  /// a [StoryServiceException] if the story moved on, was completed, is
  /// locked by someone else, or the author wrote the immediately preceding
  /// part (two consecutive turns by the same author aren't allowed).
  Future<void> submitPart({
    required String storyId,
    required String expectedPosition,
    required String text,
    required String authorEmail,
  }) {
    final docRef = _stories.doc(storyId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final story = Story.fromSnapshot(snapshot);

      if (story.status != 'incomplete') {
        throw const StoryServiceException(
            StoryServiceErrorCode.alreadyCompleted);
      }
      if (story.currentPosition != expectedPosition) {
        throw const StoryServiceException(StoryServiceErrorCode.positionTaken);
      }
      if (story.isLockedFor(authorEmail)) {
        throw const StoryServiceException(StoryServiceErrorCode.lockedByOther);
      }
      if (story.wasLastWrittenBy(authorEmail)) {
        throw const StoryServiceException(
            StoryServiceErrorCode.consecutiveTurnNotAllowed);
      }

      final newPart = StoryPart(
        position: expectedPosition,
        text: text,
        author: authorEmail,
        timestamp: Timestamp.now(),
      );
      final updatedParts = [...story.parts, newPart];
      final next = nextPosition(expectedPosition);

      transaction.update(docRef, {
        'parts': updatedParts.map((p) => p.toMap()).toList(),
        'currentPosition': next ?? expectedPosition,
        'status': next == null ? 'complete' : 'incomplete',
        'lockedBy': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
