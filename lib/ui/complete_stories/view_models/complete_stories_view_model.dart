import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/domain/models/age_rules.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/models/story_search.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// What a tap on a locked mature story led to.
enum UnlockOutcome {
  /// The user is an adult: open the story.
  open,

  /// The user is a minor: the story stays unavailable.
  minor,

  /// Nothing is known: show the birth-year screen, then call
  /// [CompleteStoriesViewModel.submitBirthYear] or
  /// [CompleteStoriesViewModel.cancelBirthYear].
  askBirthYear,

  /// Nothing to do (no user, or another check is running).
  ignored,
}

/// The result of an unlock step: what to do, and for which story.
typedef UnlockResult = ({UnlockOutcome outcome, Story story});

/// The completed stories of the room, with mature ones locked behind the
/// age check ([AgeGate]) and hidden from known minors, optionally filtered
/// by a search query ([setQuery]) on their AI title and keywords.
///
/// What the user sees for a mature story (`story.mature == true`):
/// * before the stored birth year has been read: nothing, so a minor never
///   sees a locked tile flash in and disappear;
/// * a known minor (stored birth year, or a minor verdict this session):
///   nothing;
/// * anyone else: a locked tile, until an adult verdict this session
///   unlocks every mature story at once.
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
  /// clock.
  CompleteStoriesViewModel({
    required StoryRepository storyRepository,
    required AuthRepository authRepository,
    required AgeGate ageGate,
    required String language,
    String? roomId,
    DateTime Function()? now,
  })  : _stories = storyRepository,
        _gate = ageGate,
        _email = authRepository.currentEmail,
        _now = now ?? DateTime.now,
        _language = language,
        _roomId = roomId {
    unlock = Command1<UnlockResult, Story>(_unlock);
    submitBirthYear = Command1<UnlockResult, int>(_submitBirthYear);
    _subscribe();
    _loadBirthYear();
  }

  final StoryRepository _stories;
  final AgeGate _gate;

  /// The signed-in user, read once: a sign-out tears the home screen down,
  /// and this ViewModel with it, so it can't change while we live.
  final String? _email;
  final DateTime Function() _now;

  /// The room currently listed; see [setRoom].
  String _language;
  String? _roomId;
  StreamSubscription<List<Story>>? _subscription;

  /// Set by [dispose]. Async work that finishes later (the birth-year read,
  /// an unlock step) checks it so it doesn't notify a disposed notifier.
  bool _disposed = false;

  /// Runs the age check for a locked story: platform signals first, the
  /// birth-year screen only when nothing is known. Fails if the check
  /// fails.
  late final Command1<UnlockResult, Story> unlock;

  /// Records the birth year entered for the story waiting on
  /// [UnlockOutcome.askBirthYear] and decides with it.
  late final Command1<UnlockResult, int> submitBirthYear;

  /// Every reviewed story of the room as the repository sends it (newest
  /// completed first, mature ones included); null until the first list
  /// arrives. [sections] filters and splits it for display.
  List<Story>? _all;

  /// The stored birth year, null if never asked (or the read failed).
  int? _birthYear;

  /// Whether the quiet birth-year read has finished, successfully or not.
  /// Until then mature stories are hidden from everyone.
  bool _birthYearLoaded = false;

  /// See [checkingStoryId]. Set from the first [unlock] step until the
  /// check ends, birth-year screen included.
  String? _checkingStoryId;

  /// The story whose unlock is waiting for [submitBirthYear], while the
  /// birth-year screen is open.
  Story? _awaitingBirthYear;

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
  String? get checkingStoryId => _checkingStoryId;

  /// Whether mature stories are unlocked for this session.
  bool get isUnlocked {
    final email = _email;
    return email != null && _gate.isSessionAdult(email);
  }

  /// Whether the user is known to be a minor, from either source: a minor
  /// verdict earlier this session (signal or birth year), or a stored birth
  /// year read when this ViewModel started.
  bool get _isKnownMinor {
    final email = _email;
    if (email != null && _gate.isSessionMinor(email)) return true;
    final year = _birthYear;
    return year != null && !AgeRules.isAdult(year, _now());
  }

  /// Whether [story] shows as a locked tile.
  bool isLocked(Story story) => story.mature == true && !isUnlocked;

  /// The listed stories, newest completed first, split into those the user
  /// wrote a part of and everyone else's, and filtered by the search query.
  /// Known minors don't see mature stories at all, and nobody sees them
  /// before the stored birth year is known, so a stored minor never sees a
  /// locked tile flash in. The query only narrows what that leaves, so a
  /// hidden mature story can never come back through a search.
  ({List<Story> mine, List<Story> others}) get sections => _split(_query);

  /// The size of each section without the search query (mature filtering
  /// still applied), so the View tells a room or tab without stories from
  /// one without matches. Never counts stories hidden from the user.
  ({int mine, int others}) get totalCounts {
    final (:mine, :others) = _split(StoryQuery.empty);
    return (mine: mine.length, others: others.length);
  }

  ({List<Story> mine, List<Story> others}) _split(StoryQuery query) {
    final hideMature = !_birthYearLoaded || _isKnownMinor;
    final mine = <Story>[];
    final others = <Story>[];
    // One pass keeps the repository's order inside both groups. The mature
    // check comes first: the query must never see hidden stories.
    for (final story in _all ?? const <Story>[]) {
      if (hideMature && story.mature == true) continue;
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

  /// Quietly reads the stored birth year, to hide mature stories from known
  /// minors. Never asks the platform: that may show a system sheet, so it
  /// only happens on tap.
  Future<void> _loadBirthYear() async {
    final email = _email;
    if (email != null) {
      try {
        _birthYear = await _gate.storedBirthYear(email);
      } catch (_) {
        // Unknown age: mature stories stay locked and the check runs on tap.
      }
    }
    if (_disposed) return;
    // Set even without a user or after a failed read: mature stories then
    // show as locked tiles and the full check runs on tap.
    _birthYearLoaded = true;
    notifyListeners();
  }

  /// Ends the running check, whatever its result, so other locked tiles
  /// can be tapped again and the list reflects any new verdict.
  void _finishCheck() {
    _checkingStoryId = null;
    _awaitingBirthYear = null;
    if (!_disposed) notifyListeners();
  }

  Future<UnlockResult> _unlock(Story story) async {
    final email = _email;
    // Without a user there is nobody to check; while a check runs, a tap
    // on another locked tile is ignored rather than queued.
    if (email == null || _checkingStoryId != null) {
      return (outcome: UnlockOutcome.ignored, story: story);
    }
    // Already known: answer straight away, without asking the platform
    // (which may show a system sheet) again.
    if (_isKnownMinor) return (outcome: UnlockOutcome.minor, story: story);

    // The View shows a spinner on this story's tile meanwhile.
    _checkingStoryId = story.id;
    notifyListeners();
    var awaitingBirthYear = false;
    try {
      // Platform signals first, then the stored birth year; see
      // [AgeGate.resolve] for which answer wins. Remembering the verdict
      // makes the next taps (and other mature stories) instant.
      switch (await _gate.resolve(email)) {
        case AgeVerdict.adult:
          _gate.rememberVerdict(email, adult: true);
          return (outcome: UnlockOutcome.open, story: story);
        case AgeVerdict.minor:
          _gate.rememberVerdict(email, adult: false);
          return (outcome: UnlockOutcome.minor, story: story);
        case AgeVerdict.askBirthYear:
          // The check stays running while the birth-year screen is open.
          awaitingBirthYear = true;
          _awaitingBirthYear = story;
          return (outcome: UnlockOutcome.askBirthYear, story: story);
      }
    } finally {
      // Also runs when resolve throws: the command then reports the error
      // and the tile stops spinning. Only the birth-year case keeps the
      // check open, for [submitBirthYear] or [cancelBirthYear] to close.
      if (!awaitingBirthYear) _finishCheck();
    }
  }

  Future<UnlockResult> _submitBirthYear(int birthYear) async {
    // Only reachable after [UnlockOutcome.askBirthYear], which needs a user
    // and sets the waiting story.
    final email = _email!;
    final story = _awaitingBirthYear!;
    try {
      // The year is stored once and for all (the rules refuse a second
      // write), so a child can't retry with an older year. If storing
      // fails, the command reports the error and nothing is remembered.
      final adult = await _gate.recordBirthYear(email, birthYear);
      _gate.rememberVerdict(email, adult: adult);
      return (
        outcome: adult ? UnlockOutcome.open : UnlockOutcome.minor,
        story: story,
      );
    } finally {
      _finishCheck();
    }
  }

  /// The user left the birth-year screen without answering: nothing
  /// changes.
  void cancelBirthYear() => _finishCheck();

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    unlock.dispose();
    submitBirthYear.dispose();
    super.dispose();
  }
}
