import 'package:cadavre_exquisite/domain/models/story_language.dart';

const List<String> kStoryPositions = [
  'introduzione',
  'sviluppo1',
  'sviluppo2',
  'epilogo',
];

/// Returns the position that follows [position], or null if [position] is the last one.
String? nextPosition(String position) {
  final index = kStoryPositions.indexOf(position);
  if (index == -1 || index == kStoryPositions.length - 1) return null;
  return kStoryPositions[index + 1];
}

enum StoryErrorCode {
  alreadyCompleted,
  positionTaken,
  lockedByOther,
  consecutiveTurnNotAllowed,
}

/// Thrown by `StoryRepository` operations on invalid story state. The UI
/// layer maps [code] to a localized message, so no user-facing text lives
/// here.
class StoryException implements Exception {
  final StoryErrorCode code;

  const StoryException(this.code);
}

class StoryPart {
  final String position;
  final String text;
  final String author;
  final DateTime timestamp;

  StoryPart({
    required this.position,
    required this.text,
    required this.author,
    required this.timestamp,
  });
}

class Story {
  final String id;
  final String status;
  final String currentPosition;
  final List<StoryPart> parts;
  final String? lockedBy;

  /// When [lockedBy] took the lock. Null for an unlocked story, and for
  /// locks taken by app versions older than lock expiry, which count as
  /// expired (see [isLockExpired]).
  final DateTime? lockedAt;

  final String language;

  /// Id of the private room this story belongs to, or null for a story in
  /// one of the public language rooms.
  final String? roomId;

  /// AI-generated title, set by the `reviewCompletedStory` Cloud Function
  /// shortly after the story is completed. Null until then, or if
  /// generation failed.
  final String? title;

  /// Whether the AI review judged the story unsuitable for children, set
  /// alongside [title]. Null until the story is complete and reviewed.
  final bool? mature;

  Story({
    required this.id,
    required this.status,
    required this.currentPosition,
    required this.parts,
    this.lockedBy,
    this.lockedAt,
    this.language = kDefaultStoryLanguage,
    this.roomId,
    this.title,
    this.mature,
  });

  bool get isComplete => status == 'complete';

  /// When the story was completed: the timestamp of its last part, or null
  /// if no part has been written. Part timestamps exist on every story,
  /// including those from older app versions, unlike `updatedAt`.
  DateTime? get completedAt => parts.isEmpty ? null : parts.last.timestamp;

  /// Orders stories newest completed first ([completedAt] descending),
  /// stories without parts last, ties broken by [id] ascending, so the
  /// order is fully deterministic.
  static int compareByCompletedAtDesc(Story a, Story b) {
    final aAt = a.completedAt;
    final bAt = b.completedAt;
    if (aAt != null && bAt != null) {
      final byTime = bAt.compareTo(aAt);
      if (byTime != 0) return byTime;
    } else if (aAt != null) {
      return -1;
    } else if (bAt != null) {
      return 1;
    }
    return a.id.compareTo(b.id);
  }

  /// Whether [email] wrote the most recent part, which would make this
  /// their second consecutive turn. A user may write several parts of the
  /// same story, just not two in a row.
  bool wasLastWrittenBy(String? email) =>
      email != null && parts.isNotEmpty && parts.last.author == email;

  /// Whether [email] wrote at least one part of this story.
  bool hasPartBy(String? email) =>
      email != null && parts.any((part) => part.author == email);

  /// How long a lock holds. A player who leaves the app mid-turn (or whose
  /// unlock fails) blocks the story at most this long. Must match
  /// `lockExpired()` in firestore.rules.
  static const Duration lockDuration = Duration(hours: 1);

  /// Whether the lock is older than [lockDuration], so anyone may take it.
  /// A lock without [lockedAt] (taken by an older app version) is expired.
  /// [now] defaults to the current time; tests pass a fixed one.
  bool isLockExpired({DateTime? now}) {
    final at = lockedAt;
    if (at == null) return true;
    return !(now ?? DateTime.now()).isBefore(at.add(lockDuration));
  }

  /// Whether the story is currently locked by a different user than [email]
  /// and the lock hasn't expired.
  bool isLockedFor(String? email, {DateTime? now}) =>
      lockedBy != null && lockedBy != email && !isLockExpired(now: now);

  /// Last 5 words of the most recently written part, shown as a preview
  /// to the next player. Empty if no part has been written yet.
  String get lastFiveWords {
    if (parts.isEmpty) return '';
    final words = parts.last.text.trim().split(RegExp(r'\s+'));
    final lastWords =
        words.length <= 5 ? words : words.sublist(words.length - 5);
    return lastWords.join(' ');
  }

  String get fullText => parts.map((p) => p.text).join('\n\n');
}
