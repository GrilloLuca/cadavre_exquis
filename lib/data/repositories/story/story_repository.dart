import 'package:cadavre_exquisite/domain/models/story.dart';

/// Source of truth for stories and their turns. Operations on invalid story
/// state throw a [StoryException].
abstract class StoryRepository {
  /// Incomplete stories in the room identified by [language]/[roomId]: the
  /// private room [roomId] when given, otherwise the public [language] room.
  Stream<List<Story>> incompleteStoriesStream({
    required String language,
    String? roomId,
  });

  /// Completed stories of the room with a `mature` verdict, both mature and
  /// not (the UI locks the former behind the age check), newest completed
  /// first (see [Story.compareByCompletedAtDesc]). Stories without a
  /// verdict are left out; stories flagged by a part but still awaiting the
  /// completion review ([Story.awaitingReview]) may be included, and the UI
  /// drops them.
  Stream<List<Story>> completeStoriesStream({
    required String language,
    String? roomId,
  });

  /// The story with [storyId], or null if there is none.
  Future<Story?> getStory(String storyId);

  /// Creates an empty story and returns it, so the caller can open it
  /// straight away.
  Future<Story> createStory({required String language, String? roomId});

  /// Exclusively locks the story for [authorEmail] so no one else can open
  /// or edit it while they're writing their part. The lock expires after
  /// [Story.lockDuration]. Throws a [StoryException] if the story was
  /// completed, its latest part awaits the AI review
  /// ([StoryErrorCode.underReview]), it has an unexpired lock held by
  /// someone else, or the author wrote the immediately preceding part.
  Future<void> lockStory(
      {required String storyId, required String authorEmail});

  /// Releases the lock held by [authorEmail]. No-op if the story is
  /// unlocked already or held by someone else.
  Future<void> unlockStory({
    required String storyId,
    required String authorEmail,
  });

  /// Appends the next part of the story at [expectedPosition], completing
  /// the story after the last position and releasing the lock. Throws a
  /// [StoryException] if the story moved on, was completed, its latest part
  /// awaits the AI review, it is locked by someone else, or the author
  /// wrote the immediately preceding part.
  Future<void> submitPart({
    required String storyId,
    required String expectedPosition,
    required String text,
    required String authorEmail,
  });
}
