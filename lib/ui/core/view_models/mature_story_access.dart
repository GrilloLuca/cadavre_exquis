import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/domain/models/age_rules.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';

/// How a story shows to the signed-in user, as far as its `mature` flag is
/// concerned (see docs/PART_MODERATION_PLAN.md, D4b). Whether a known minor
/// gets [unavailable] or [hidden] depends on
/// [MatureStoryAccess.visibleToMinors].
enum MatureTileState {
  /// Not mature (`mature != true`): shown as any other story.
  none,

  /// Mature, and the user is a known minor: a disabled padlocked tile that
  /// never calls the age check.
  unavailable,

  /// Mature, the user is a known minor and mature stories are hidden from
  /// minors ([MatureStoryAccess.visibleToMinors] false): not listed at all,
  /// nor matched by a search, nor counted.
  hidden,

  /// Mature, and the user's age is unknown (including while the stored
  /// birth year is still being read): a padlocked tile, tap → age check.
  locked,

  /// Mature, and the user was found adult this session.
  unlocked,
}

/// What a tap on a locked mature story led to.
enum UnlockOutcome {
  /// The user is an adult: open the story.
  open,

  /// The user is a minor: the story stays unavailable.
  minor,

  /// Nothing is known: show the birth-year screen, then call
  /// [MatureStoryAccess.submitBirthYear] or
  /// [MatureStoryAccess.cancelBirthYear].
  askBirthYear,

  /// Nothing to do (no user, or another check is running).
  ignored,
}

/// The result of an unlock step: what to do, and for which story.
typedef UnlockResult = ({UnlockOutcome outcome, Story story});

/// The mature-story gate shared by the story lists and the notification
/// router: who is a known minor or a session adult, the [MatureTileState]
/// of each story, and the unlock flow through [AgeGate].
///
/// Not a ViewModel itself: each ViewModel owns one, wraps [unlock] and
/// [submitBirthYear] in its `Command`s and passes [onChanged] (its own
/// `notifyListeners`), so the View rebuilds when the read finishes or a
/// check starts or ends.
///
/// A known minor is a user with a stored birth year that isn't adult (read
/// quietly by [loadBirthYear], never asking the platform) or a minor
/// verdict this session ([AgeGate.isSessionMinor]). Session verdicts live
/// in the app-wide [AgeGate], so a verdict given in one list holds in the
/// other and in the router, and is forgotten on sign-out.
///
/// Unlocking takes one or two steps, because the View may have to show the
/// birth-year screen in between:
/// 1. [unlock] asks the gate. Its result says to open the story, to tell
///    the user it's unavailable, or to ask the birth year
///    ([UnlockOutcome.askBirthYear]).
/// 2. After the birth-year screen the View calls [submitBirthYear] with
///    the year, or [cancelBirthYear] if the user went back.
class MatureStoryAccess {
  /// [now] decides adulthood from a stored birth year; tests pass a fixed
  /// clock.
  ///
  /// [visibleToMinors] chooses what known minors get for a mature story:
  /// a disabled [MatureTileState.unavailable] tile (true, the default) or
  /// nothing at all ([MatureTileState.hidden], false). The app sets it from
  /// the `MATURE_VISIBLE_TO_MINORS` build flag (see
  /// `lib/config/dependencies.dart`). Either way a minor's tap or
  /// notification gets [UnlockOutcome.minor].
  MatureStoryAccess({
    required AgeGate ageGate,
    required AuthRepository authRepository,
    required void Function() onChanged,
    DateTime Function()? now,
    this.visibleToMinors = true,
  })  : _gate = ageGate,
        _auth = authRepository,
        _onChanged = onChanged,
        _now = now ?? DateTime.now;

  /// Whether known minors see mature stories, as unavailable tiles, rather
  /// than not at all.
  final bool visibleToMinors;

  final AgeGate _gate;
  final AuthRepository _auth;
  final void Function() _onChanged;
  final DateTime Function() _now;

  /// Set by [dispose]. Async work that finishes later (the birth-year read,
  /// an unlock step) checks it so it doesn't notify a disposed owner.
  bool _disposed = false;

  /// The stored birth year, null if never asked, not read yet, or the read
  /// failed.
  int? _birthYear;

  /// See [checkingStoryId]. Set from the first [unlock] step until the
  /// check ends, birth-year screen included.
  String? _checkingStoryId;

  /// The story whose unlock is waiting for [submitBirthYear], while the
  /// birth-year screen is open.
  Story? _awaitingBirthYear;

  String? get _email => _auth.currentEmail;

  /// The story waiting for [submitBirthYear], null when no birth-year
  /// screen is open.
  Story? get awaitingBirthYear => _awaitingBirthYear;

  /// Id of the mature story whose age check is running, null when idle.
  /// Only one check runs at a time.
  String? get checkingStoryId => _checkingStoryId;

  /// Whether the user was found adult this session: every mature story is
  /// unlocked.
  bool get isSessionAdult {
    final email = _email;
    return email != null && _gate.isSessionAdult(email);
  }

  /// Whether the user is known to be a minor, from either source: a minor
  /// verdict this session (signal or birth year), or the stored birth year
  /// read by [loadBirthYear].
  bool get isKnownMinor {
    final email = _email;
    if (email != null && _gate.isSessionMinor(email)) return true;
    final year = _birthYear;
    return year != null && !AgeRules.isAdult(year, _now());
  }

  /// How [story] shows: see [MatureTileState]. Until [loadBirthYear] has
  /// finished, a stored minor counts as unknown age and gets locked tiles;
  /// a tap then is still safe, since [AgeGate.resolve] reads the stored
  /// year itself and answers minor without asking the platform.
  ///
  /// With [visibleToMinors] false, a known minor's mature stories are
  /// [MatureTileState.hidden]: after a minor verdict from a tap they
  /// disappear (the View shows its snackbar once), and while the stored
  /// birth year is still being read they show as locked, as above.
  MatureTileState stateOf(Story story) {
    if (story.mature != true) return MatureTileState.none;
    if (isKnownMinor) {
      return visibleToMinors
          ? MatureTileState.unavailable
          : MatureTileState.hidden;
    }
    if (isSessionAdult) return MatureTileState.unlocked;
    return MatureTileState.locked;
  }

  /// Whether [story] is listed at all: false only for a
  /// [MatureTileState.hidden] story.
  bool isListed(Story story) => stateOf(story) != MatureTileState.hidden;

  /// Quietly reads the stored birth year, so known minors get unavailable
  /// (or hidden) tiles. Never asks the platform: that may show a system sheet, so it
  /// only happens on tap. A failed read leaves the age unknown (mature
  /// stories locked, the full check on tap). Calls [onChanged] when done;
  /// may be called again to refresh.
  Future<void> loadBirthYear() async {
    final email = _email;
    if (email != null) {
      try {
        _birthYear = await _gate.storedBirthYear(email);
      } catch (_) {
        // Unknown age: mature stories stay locked and the check runs on tap.
      }
    }
    if (!_disposed) _onChanged();
  }

  /// Ends the running check, whatever its result, so other locked tiles
  /// can be tapped again and the list reflects any new verdict.
  void _finishCheck() {
    _checkingStoryId = null;
    _awaitingBirthYear = null;
    if (!_disposed) _onChanged();
  }

  /// Runs the age check for the locked [story]: platform signals first,
  /// the birth-year screen only when nothing is known. Throws if the check
  /// fails. A known minor gets [UnlockOutcome.minor] straight away, without
  /// calling [AgeGate.resolve].
  Future<UnlockResult> unlock(Story story) async {
    final email = _email;
    // Without a user there is nobody to check; while a check runs, a tap
    // on another locked tile is ignored rather than queued.
    if (email == null || _checkingStoryId != null) {
      return (outcome: UnlockOutcome.ignored, story: story);
    }
    // Already known: answer straight away, without asking the platform
    // (which may show a system sheet) again.
    if (isKnownMinor) return (outcome: UnlockOutcome.minor, story: story);

    // The View shows a spinner on this story's tile meanwhile.
    _checkingStoryId = story.id;
    _onChanged();
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

  /// Records the birth year entered for the story waiting on
  /// [UnlockOutcome.askBirthYear] ([awaitingBirthYear]) and decides with
  /// it. Only valid while a story is waiting: throws a [StateError]
  /// otherwise.
  Future<UnlockResult> submitBirthYear(int birthYear) async {
    final email = _email;
    final story = _awaitingBirthYear;
    if (email == null || story == null) {
      throw StateError('No age check is waiting for a birth year');
    }
    try {
      // The year is stored once and for all (the rules refuse a second
      // write), so a child can't retry with an older year. If storing
      // fails, the error is thrown and nothing is remembered.
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

  void dispose() => _disposed = true;
}
