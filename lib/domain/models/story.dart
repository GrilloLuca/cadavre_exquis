import 'package:cadavre_exquisite/domain/models/email_key.dart';
import 'package:cadavre_exquisite/domain/models/story_language.dart';

const List<String> kStoryPositions = [
  'introduzione',
  'sviluppo1',
  'sviluppo2',
  'epilogo',
];

/// Most characters a part may have. Must match `part.text.size() <= 5000`
/// in firestore.rules.
const int kMaxPartLength = 5000;

/// Fewest words a part may have: the next player sees the last five, so a
/// shorter part leaves them less to continue from. Checked by the app only.
const int kMinPartWords = 5;

/// The number of words in [text], separated by whitespace.
int wordCount(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty ? 0 : trimmed.split(RegExp(r'\s+')).length;
}

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

  /// The story's latest part has no AI verdict yet, so nobody may open it
  /// (see [Story.awaitingReview]).
  underReview,
}

/// The AI verdict on one part of a story, stored by the server in the
/// story's `partReviews`.
enum PartVerdict { safe, mature }

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

  /// Whether moderation removed the part after a report: its [text] is
  /// empty and the app says it was removed instead (see
  /// functions/src/reports.ts). False on every legacy part.
  final bool removed;

  StoryPart({
    required this.position,
    required this.text,
    required this.author,
    required this.timestamp,
    this.removed = false,
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

  /// Whether the story is unsuitable for children. Set to true as soon as
  /// the AI review flags one of its parts (incomplete stories included), or
  /// by the completion review alongside [title], which sets false when
  /// nothing was flagged. Never goes back from true to false. Null while no
  /// review has flagged or cleared it.
  final bool? mature;

  /// The AI verdict on each reviewed part, keyed by part position. Empty
  /// for legacy stories and until the first verdict lands.
  final Map<String, PartVerdict> partReviews;

  /// When the completion review (or the legacy backfill) marked the
  /// complete story as reviewed. Null for incomplete stories and until
  /// then.
  final DateTime? reviewedAt;

  /// Up to 4 AI-generated keywords describing the parts written so far,
  /// set by the `extractStoryKeywords` Cloud Function shortly after each
  /// part, the last one included (so a completed story has keywords for
  /// the whole story). Empty until then, if extraction failed or gave
  /// nothing usable, and for legacy stories not yet backfilled.
  final List<String> keywords;

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
    this.partReviews = const {},
    this.reviewedAt,
    this.keywords = const [],
  });

  bool get isComplete => status == 'complete';

  /// Whether the story can't be opened yet because the AI review hasn't
  /// judged it: a complete story until [reviewedAt] is set; an incomplete
  /// one while its latest part has no verdict in [partReviews] (one without
  /// parts has nothing to review). Mirrors `lastPartReviewed` in
  /// firestore.rules, which refuses locks and submits meanwhile.
  bool get awaitingReview => isComplete
      ? reviewedAt == null
      : parts.isNotEmpty && !partReviews.containsKey(parts.last.position);

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

  /// Whether one of the parts was written by a user whose [emailKey] is in
  /// [keys], e.g. someone the signed-in user blocked.
  bool hasPartByAnyOf(Set<String> keys) =>
      keys.isNotEmpty &&
      parts.any((part) => keys.contains(emailKey(part.author)));

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

  /// Whether the most recently written part was removed by moderation, so
  /// there are no [lastFiveWords] to show.
  bool get lastPartRemoved => parts.isNotEmpty && parts.last.removed;

  /// Last 5 words of the most recently written part, shown as a preview
  /// to the next player. Empty if no part has been written yet, or if it
  /// was removed ([lastPartRemoved]).
  String get lastFiveWords {
    if (parts.isEmpty) return '';
    final words = parts.last.text.trim().split(RegExp(r'\s+'));
    final lastWords =
        words.length <= 5 ? words : words.sublist(words.length - 5);
    return lastWords.join(' ');
  }

  String get fullText => parts.map((p) => p.text).join('\n\n');
}
