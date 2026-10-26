import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/safety/safety_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/models/story_search.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/ui/core/view_models/mature_story_access.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// The completed stories of the room that the AI review has finished
/// reading ([Story.awaitingReview] is false), with mature ones locked behind
/// the age check ([AgeGate], through [MatureStoryAccess]), optionally
/// filtered by a search query ([setQuery]) on their AI title and keywords.
///
/// What the user sees for a mature story (`story.mature == true`), see
/// [MatureTileState] and docs/PART_MODERATION_PLAN.md D4b:
/// * a known minor (stored birth year, or a minor verdict this session): a
///   disabled, padlocked "unavailable" tile that never calls the gate, or,
///   when [MatureStoryAccess.visibleToMinors] is false, nothing: the story
///   isn't listed, matched by the search or counted;
/// * anyone else, including before the stored birth year has been read: a
///   locked tile, until an adult verdict this session unlocks every mature
///   story at once.
///
/// Unlocking takes one or two steps, because the View may have to show the
/// birth-year screen in between:
/// 1. [unlock] asks the gate. Its result says to open the story, to tell
///    the user it's unavailable, or to ask the birth year
///    ([UnlockOutcome.askBirthYear]).
/// 2. After the birth-year screen the View calls [submitBirthYear] with
///    the year, or [cancelBirthYear] if the user went back.
///
/// The session's verdicts live in the app-wide [AgeGate], not here, so they
/// survive this ViewModel being recreated (room change, tab rebuilt) and
/// are forgotten on sign-out.
class CompleteStoriesViewModel extends ChangeNotifier {
  /// [now] decides adulthood from a stored birth year; tests pass a fixed
  /// clock. [matureVisibleToMinors]: see [MatureStoryAccess.visibleToMinors].
  CompleteStoriesViewModel({
    required StoryRepository storyRepository,
    required AuthRepository authRepository,
    required SafetyRepository safetyRepository,
    required AgeGate ageGate,
    required String language,
    String? roomId,
    DateTime Function()? now,
    bool matureVisibleToMinors = true,
  })  : _stories = storyRepository,
        _safety = safetyRepository,
        _email = authRepository.currentEmail,
        _language = language,
        _roomId = roomId {
    _access = MatureStoryAccess(
      ageGate: ageGate,
      authRepository: authRepository,
      now: now,
      onChanged: notifyListeners,
      visibleToMinors: matureVisibleToMinors,
    );
    unlock = Command1<UnlockResult, Story>(_access.unlock);
    submitBirthYear = Command1<UnlockResult, int>(_access.submitBirthYear);
    _safety.addListener(notifyListeners);
    _subscribe();
    _access.loadBirthYear();
  }

  final StoryRepository _stories;

  /// Stories with a part by an author the user blocked are never listed.
  final SafetyRepository _safety;

  /// The mature-story gate: tile states, the stored-year read and the
  /// unlock flow.
  late final MatureStoryAccess _access;

  /// The signed-in user, read once: a sign-out tears the home screen down,
  /// and this ViewModel with it, so it can't change while we live.
  final String? _email;

  /// The room currently listed; see [setRoom].
  String _language;
  String? _roomId;
  StreamSubscription<List<Story>>? _subscription;

  /// Runs the age check for a locked story: platform signals first, the
  /// birth-year screen only when nothing is known. Fails if the check
  /// fails.
  late final Command1<UnlockResult, Story> unlock;

  /// Records the birth year entered for the story waiting on
  /// [UnlockOutcome.askBirthYear] and decides with it.
  late final Command1<UnlockResult, int> submitBirthYear;

  /// Every story of the room as the repository sends it (newest completed
  /// first, mature ones included, possibly some still awaiting their
  /// completion review); null until the first list arrives. [sections]
  /// filters and splits it for display.
  List<Story>? _all;

  /// The search typed by the user; see [setQuery]. Reset by a room change.
  StoryQuery _query = StoryQuery.empty;

  /// The raw text of the current search, as last passed to [setQuery].
  String get query => _query.text;

  /// Whether a search filters the lists, i.e. the query has at least one
  /// word. An empty or whitespace-only query lists everything.
  bool get isSearching => !_query.isEmpty;

  /// Whether [keyword] matches the current search, so the View can
  /// highlight it. Always false when not searching.
  bool highlights(String keyword) => _query.highlights(keyword);

  /// Whether the room's stories have arrived.
  bool get isLoaded => _all != null;

  /// Id of the mature story whose age check is running, null when idle.
  /// Only one check runs at a time.
  String? get checkingStoryId => _access.checkingStoryId;

  /// Whether mature stories are unlocked for this session.
  bool get isUnlocked => _access.isSessionAdult;

  /// How the mature-story gate shows [story]: see [MatureTileState].
  MatureTileState matureStateOf(Story story) => _access.stateOf(story);

  /// Whether [story] shows as a locked tile (tap → age check).
  bool isLocked(Story story) => matureStateOf(story) == MatureTileState.locked;

  /// The listed stories, newest completed first, split into those the user
  /// wrote a part of and everyone else's, and filtered by the search query.
  /// Stories still awaiting their completion review are never listed, nor
  /// matched, nor counted. Mature stories stay listed for everyone, known
  /// minors included (as unavailable tiles), so they match the query on
  /// their child-safe AI title and keywords like any other; unless they are
  /// hidden from known minors ([MatureTileState.hidden]), which leaves them
  /// out like the unreviewed ones.
  ({List<Story> mine, List<Story> others}) get sections => _split(_query);

  /// The size of each section without the search query, so the View tells
  /// a room or tab without stories from one without matches. Counts mature
  /// stories, unavailable ones included; never counts stories awaiting
  /// their review nor hidden ones.
  ({int mine, int others}) get totalCounts {
    final (:mine, :others) = _split(StoryQuery.empty);
    return (mine: mine.length, others: others.length);
  }

  ({List<Story> mine, List<Story> others}) _split(StoryQuery query) {
    final mine = <Story>[];
    final others = <Story>[];
    // One pass keeps the repository's order inside both groups. The review
    // check comes first: the query must never see unreviewed stories.
    final blocked = _safety.blockedKeys;
    for (final story in _all ?? const <Story>[]) {
      if (story.awaitingReview) continue;
      if (story.hasPartByAnyOf(blocked)) continue;
      if (!_access.isListed(story)) continue;
      if (!query.matches(story)) continue;
      (story.hasPartBy(_email) ? mine : others).add(story);
    }
    return (mine: mine, others: others);
  }

  /// Filters both sections by [text] (see [StoryQuery]: AI title and
  /// keywords, folded case and accents, word prefixes, every word must
  /// match). Notifies only when the effective query changes, so typing a
  /// trailing space or a short article doesn't rebuild the lists.
  void setQuery(String text) {
    final query = StoryQuery(text);
    final changed = !_query.hasSameTokens(query);
    _query = query;
    if (changed) notifyListeners();
  }

  /// Switches to the room identified by [language]/[roomId]. Called by the
  /// View on every rebuild of the tab, so it does nothing when the room is
  /// the same. Age verdicts are per user, not per room: an unlock carries
  /// over to the new room. The search query is cleared: rooms are often in
  /// another language, and an old query would quietly hide stories.
  void setRoom({required String language, String? roomId}) {
    if (language == _language && roomId == _roomId) return;
    _language = language;
    _roomId = roomId;
    _query = StoryQuery.empty;
    // Back to the spinner rather than showing the old room's stories while
    // the new ones load.
    _all = null;
    _subscribe();
    notifyListeners();
  }

  /// Listens to the current room's stories, dropping the previous room's
  /// subscription so a late snapshot from it can't overwrite the list.
  void _subscribe() {
    _subscription?.cancel();
    _subscription = _stories
        .completeStoriesStream(language: _language, roomId: _roomId)
        .listen((stories) {
      _all = stories;
      notifyListeners();
    }, onError: (Object _) {
      // As before this ViewModel: a failed stream leaves the last list (or
      // the spinner) on screen.
    });
  }

  /// The user left the birth-year screen without answering: nothing
  /// changes.
  void cancelBirthYear() => _access.cancelBirthYear();

  @override
  void dispose() {
    _safety.removeListener(notifyListeners);
    _access.dispose();
    _subscription?.cancel();
    unlock.dispose();
    submitBirthYear.dispose();
    super.dispose();
  }
}
