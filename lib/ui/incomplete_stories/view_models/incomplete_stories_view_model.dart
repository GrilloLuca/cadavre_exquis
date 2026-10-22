import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/ui/core/view_models/mature_story_access.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// Whether the signed-in user can open an incomplete story, first match
/// wins in this order: [unavailable], [underReview], [beingWritten] /
/// [waitingForOthers], [locked], [available] (see
/// docs/PART_MODERATION_UI_SPEC.md §2.1).
enum IncompleteStoryStatus {
  /// The user can write its next part. A mature story is [available] only
  /// to a session adult (see [IncompleteStoriesViewModel.matureStateOf]).
  available,

  /// Someone else holds an unexpired lock on it.
  beingWritten,

  /// The user wrote the last part and must wait for someone else's turn.
  waitingForOthers,

  /// Its latest part awaits the AI review: nobody can open it yet.
  underReview,

  /// Mature, and the user's age is unknown: tap → age check.
  locked,

  /// Mature, and the user is a known minor: never opens, and never calls
  /// the age check. Comes first because `mature` is never downgraded,
  /// whatever a pending review says.
  unavailable,
}

/// The incomplete stories of the user's room, and creating new ones.
///
/// Stories whose latest part is still being reviewed are listed but can't
/// be opened ([IncompleteStoryStatus.underReview]). Mature stories (a part
/// was flagged) go through the same age check as the completed stories
/// list, via [MatureStoryAccess]: locked for unknown age ([unlock], then
/// [submitBirthYear] or [cancelBirthYear]), unavailable to known minors,
/// or not listed for them at all when [matureVisibleToMinors] is false.
class IncompleteStoriesViewModel extends ChangeNotifier {
  /// [now] decides whether a lock has expired and adulthood from a stored
  /// birth year; tests pass a fixed clock. [matureVisibleToMinors]: see
  /// [MatureStoryAccess.visibleToMinors].
  IncompleteStoriesViewModel({
    required StoryRepository storyRepository,
    required AuthRepository authRepository,
    required AgeGate ageGate,
    required String language,
    String? roomId,
    DateTime Function()? now,
    bool matureVisibleToMinors = true,
  })  : _stories = storyRepository,
        _auth = authRepository,
        _now = now ?? DateTime.now,
        _language = language,
        _roomId = roomId {
    _access = MatureStoryAccess(
      ageGate: ageGate,
      authRepository: authRepository,
      now: _now,
      onChanged: notifyListeners,
      visibleToMinors: matureVisibleToMinors,
    );
    createStory = Command0<Story>(_createStory);
    unlock = Command1<UnlockResult, Story>(
        (story) async => _latest(await _access.unlock(story)));
    submitBirthYear = Command1<UnlockResult, int>(
        (year) async => _latest(await _access.submitBirthYear(year)));
    _subscribe();
    _access.loadBirthYear();
  }

  final StoryRepository _stories;
  final AuthRepository _auth;
  final DateTime Function() _now;

  /// The mature-story gate: tile states, the stored-year read and the
  /// unlock flow.
  late final MatureStoryAccess _access;

  /// Runs the age check for a locked mature story (see
  /// [MatureStoryAccess.unlock]). Its story is the latest one listed with
  /// that id, so the chat opens on what's current. Fails if the check
  /// fails.
  late final Command1<UnlockResult, Story> unlock;

  /// Records the birth year entered for the story waiting on
  /// [UnlockOutcome.askBirthYear] and decides with it.
  late final Command1<UnlockResult, int> submitBirthYear;

  String _language;
  String? _roomId;
  StreamSubscription<List<Story>>? _subscription;

  /// Creates an empty story in the room, or reuses one nobody has started
  /// yet; its value is the story, to open straight away.
  late final Command0<Story> createStory;

  /// Every incomplete story of the room, least written first, hidden
  /// mature ones included; null until the first list arrives.
  List<Story>? _list;

  /// The room's incomplete stories, least written first. Null until the
  /// first list arrives. Leaves out the mature stories hidden from a known
  /// minor ([MatureTileState.hidden]), so an empty result shows the empty
  /// state.
  List<Story>? get stories => _list?.where(_access.isListed).toList();

  /// Switches to the room identified by [language]/[roomId]: the private
  /// room [roomId] when given, otherwise the public [language] room.
  void setRoom({required String language, String? roomId}) {
    if (language == _language && roomId == _roomId) return;
    _language = language;
    _roomId = roomId;
    _list = null;
    _subscribe();
    notifyListeners();
  }

  void _subscribe() {
    _subscription?.cancel();
    _subscription = _stories
        .incompleteStoriesStream(language: _language, roomId: _roomId)
        .listen((stories) {
      _list = stories.toList()
        ..sort((a, b) => a.parts.length.compareTo(b.parts.length));
      notifyListeners();
    }, onError: (Object _) {
      // As before this ViewModel: a failed stream leaves the last list (or
      // the spinner) on screen.
    });
  }

  /// Id of the mature story whose age check is running, null when idle.
  String? get checkingStoryId => _access.checkingStoryId;

  /// How the mature-story gate shows [story]: see [MatureTileState]. The
  /// View uses it for the padlock of a disabled tile and the open padlock
  /// of an unlocked one.
  MatureTileState matureStateOf(Story story) => _access.stateOf(story);

  /// What the signed-in user can do with [story] right now, in the order
  /// documented on [IncompleteStoryStatus]. Computed on each call, so an
  /// expired lock frees the story on the next rebuild.
  IncompleteStoryStatus statusOf(Story story) {
    final email = _auth.currentEmail;
    final mature = _access.stateOf(story);
    // A hidden story isn't listed; should a View still ask, it can't open.
    if (mature == MatureTileState.unavailable ||
        mature == MatureTileState.hidden) {
      return IncompleteStoryStatus.unavailable;
    }
    if (story.awaitingReview) return IncompleteStoryStatus.underReview;
    if (story.isLockedFor(email, now: _now())) {
      return IncompleteStoryStatus.beingWritten;
    }
    if (story.wasLastWrittenBy(email)) {
      return IncompleteStoryStatus.waitingForOthers;
    }
    if (mature == MatureTileState.locked) return IncompleteStoryStatus.locked;
    return IncompleteStoryStatus.available;
  }

  /// Whether the user may start a new story: not before the room list has
  /// arrived, nor while an introduction they wrote is still waiting for
  /// its second part. A flagged (mature) introduction doesn't count: only
  /// adults can continue it, so it may wait a long time, and a minor who
  /// wrote it sees it as unavailable (or not at all).
  bool get canCreateStory {
    final list = _list;
    if (list == null) return false;
    final email = _auth.currentEmail;
    return !list.any((story) =>
        story.mature != true &&
        story.parts.length == 1 &&
        story.parts.first.author == email);
  }

  /// [result] with its story replaced by the latest listed one with the
  /// same id, if still listed.
  UnlockResult _latest(UnlockResult result) {
    for (final story in _list ?? const <Story>[]) {
      if (story.id == result.story.id) {
        return (outcome: result.outcome, story: story);
      }
    }
    return result;
  }

  /// The user left the birth-year screen without answering: nothing
  /// changes.
  void cancelBirthYear() => _access.cancelBirthYear();

  /// Reuses an empty story the user can open rather than piling up another
  /// one; creates a story only when there is none.
  Future<Story> _createStory() async {
    final email = _auth.currentEmail;
    final now = _now();
    for (final story in _list ?? const <Story>[]) {
      if (story.parts.isEmpty && !story.isLockedFor(email, now: now)) {
        return story;
      }
    }
    return _stories.createStory(language: _language, roomId: _roomId);
  }

  @override
  void dispose() {
    _access.dispose();
    _subscription?.cancel();
    createStory.dispose();
    unlock.dispose();
    submitBirthYear.dispose();
    super.dispose();
  }
}
