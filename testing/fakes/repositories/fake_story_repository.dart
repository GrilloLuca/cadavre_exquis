import 'dart:async';

import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';

/// In-memory [StoryRepository] for ViewModel and widget tests. Applies the
/// same turn rules as the Firestore implementation (a story awaiting the AI
/// review included); [now] decides lock expiry, [failWith] makes every
/// write throw, and [review] and [put] stand in for server writes.
class FakeStoryRepository implements StoryRepository {
  FakeStoryRepository({Iterable<Story> stories = const [], this.now})
      : _stories = {for (final story in stories) story.id: story};

  final Map<String, Story> _stories;
  final _changes = StreamController<void>.broadcast();
  int _nextId = 0;

  DateTime Function()? now;

  /// When set, every write throws it instead of changing anything.
  Object? failWith;

  /// The stored stories, by id.
  Map<String, Story> get stories => Map.unmodifiable(_stories);

  /// Replaces (or adds) [story] and notifies the streams, as a server write
  /// would: e.g. an AI verdict landing in `partReviews`, `mature` or
  /// `reviewedAt`.
  void put(Story story) => _put(story);

  /// Stores [verdict] on the latest part of the story [storyId], as the
  /// server's review does: a mature verdict also sets `mature: true`, and a
  /// complete story gets its `reviewedAt` (and `mature: false` if nothing
  /// was flagged).
  void review(String storyId, {PartVerdict verdict = PartVerdict.safe}) {
    final story = _stories[storyId]!;
    final flagged = verdict == PartVerdict.mature || story.mature == true;
    _put(_copy(
      story,
      partReviews: {
        ...story.partReviews,
        if (story.parts.isNotEmpty) story.parts.last.position: verdict,
      },
      mature: flagged ? true : (story.isComplete ? false : story.mature),
      reviewedAt: story.isComplete ? _now() : story.reviewedAt,
    ));
  }

  DateTime _now() => (now ?? DateTime.now)();

  /// Emits [select] on listen and after every write. Subscribes to the
  /// changes synchronously, so writes right after `listen` aren't missed.
  Stream<List<Story>> _watch(List<Story> Function() select) {
    late final StreamController<List<Story>> controller;
    StreamSubscription<void>? changes;
    controller = StreamController<List<Story>>(
      onListen: () {
        controller.add(select());
        changes = _changes.stream.listen((_) => controller.add(select()));
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  bool _inRoom(Story story, String language, String? roomId) => roomId != null
      ? story.roomId == roomId
      : story.language == language && story.roomId == null;

  @override
  Stream<List<Story>> incompleteStoriesStream({
    required String language,
    String? roomId,
  }) =>
      _watch(() => _stories.values
          .where((s) => !s.isComplete && _inRoom(s, language, roomId))
          .toList());

  @override
  Stream<List<Story>> completeStoriesStream({
    required String language,
    String? roomId,
  }) =>
      _watch(() => _stories.values
          // Like the Firestore query, which filters on `mature` only:
          // stories awaiting the completion review can be included.
          .where((s) =>
              s.isComplete && s.mature != null && _inRoom(s, language, roomId))
          .toList()
        ..sort(Story.compareByCompletedAtDesc));

  void _put(Story story) {
    _stories[story.id] = story;
    _changes.add(null);
  }

  void _checkFailure() {
    final failure = failWith;
    if (failure != null) throw failure;
  }

  @override
  Future<Story?> getStory(String storyId) async => _stories[storyId];

  @override
  Future<Story> createStory({required String language, String? roomId}) async {
    _checkFailure();
    final story = Story(
      id: 'fake-${_nextId++}',
      status: 'incomplete',
      currentPosition: kStoryPositions.first,
      parts: const [],
      language: language,
      roomId: roomId,
    );
    _put(story);
    return story;
  }

  @override
  Future<void> lockStory({
    required String storyId,
    required String authorEmail,
  }) async {
    _checkFailure();
    final story = _stories[storyId]!;
    if (story.isComplete) {
      throw const StoryException(StoryErrorCode.alreadyCompleted);
    }
    if (story.awaitingReview) {
      throw const StoryException(StoryErrorCode.underReview);
    }
    if (story.wasLastWrittenBy(authorEmail)) {
      throw const StoryException(StoryErrorCode.consecutiveTurnNotAllowed);
    }
    if (story.isLockedFor(authorEmail, now: _now())) {
      throw const StoryException(StoryErrorCode.lockedByOther);
    }
    _put(_copy(story, lockedBy: authorEmail, lockedAt: _now()));
  }

  @override
  Future<void> unlockStory({
    required String storyId,
    required String authorEmail,
  }) async {
    _checkFailure();
    final story = _stories[storyId]!;
    if (story.lockedBy == authorEmail) {
      _put(_copy(story, lockedBy: null, lockedAt: null));
    }
  }

  @override
  Future<void> submitPart({
    required String storyId,
    required String expectedPosition,
    required String text,
    required String authorEmail,
  }) async {
    _checkFailure();
    final story = _stories[storyId]!;
    if (story.isComplete) {
      throw const StoryException(StoryErrorCode.alreadyCompleted);
    }
    if (story.currentPosition != expectedPosition) {
      throw const StoryException(StoryErrorCode.positionTaken);
    }
    if (story.awaitingReview) {
      throw const StoryException(StoryErrorCode.underReview);
    }
    if (story.isLockedFor(authorEmail, now: _now())) {
      throw const StoryException(StoryErrorCode.lockedByOther);
    }
    if (story.wasLastWrittenBy(authorEmail)) {
      throw const StoryException(StoryErrorCode.consecutiveTurnNotAllowed);
    }
    final next = nextPosition(expectedPosition);
    _put(_copy(
      story,
      status: next == null ? 'complete' : 'incomplete',
      currentPosition: next ?? expectedPosition,
      parts: [
        ...story.parts,
        StoryPart(
          position: expectedPosition,
          text: text,
          author: authorEmail,
          timestamp: _now(),
        ),
      ],
      lockedBy: null,
      lockedAt: null,
    ));
  }
}

const _keep = Object();

Story _copy(
  Story story, {
  String? status,
  String? currentPosition,
  List<StoryPart>? parts,
  Object? lockedBy = _keep,
  Object? lockedAt = _keep,
  Map<String, PartVerdict>? partReviews,
  bool? mature,
  DateTime? reviewedAt,
}) =>
    Story(
      id: story.id,
      status: status ?? story.status,
      currentPosition: currentPosition ?? story.currentPosition,
      parts: parts ?? story.parts,
      lockedBy:
          identical(lockedBy, _keep) ? story.lockedBy : lockedBy as String?,
      lockedAt:
          identical(lockedAt, _keep) ? story.lockedAt : lockedAt as DateTime?,
      language: story.language,
      roomId: story.roomId,
      title: story.title,
      mature: mature ?? story.mature,
      partReviews: partReviews ?? story.partReviews,
      reviewedAt: reviewedAt ?? story.reviewedAt,
      keywords: story.keywords,
    );
