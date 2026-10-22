import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/notification/notification_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/models/story_notification.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/ui/core/view_models/mature_story_access.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// Where a tapped notification leads.
enum StoryLinkOutcome {
  /// Open the story to write its next part.
  write,

  /// Open the completed story to read it.
  read,

  /// The story is mature and nothing is known about the user's age: show
  /// the birth-year screen, then call
  /// [NotificationRouterViewModel.submitBirthYear] or
  /// [NotificationRouterViewModel.cancelBirthYear].
  askBirthYear,

  /// The story is mature and the user is a minor.
  matureUnavailable,

  /// The story no longer exists.
  notFound,

  /// The story isn't complete or reviewed yet, so it can't be read.
  notReadyYet,

  /// The story's latest part is still being reviewed, so it can't be
  /// written yet.
  underReview,

  /// The story was completed meanwhile: there's nothing left to write.
  alreadyCompleted,

  /// Someone else is writing the next part right now.
  lockedByOther,

  /// The user wrote the last part themselves meanwhile.
  alreadyContinued,

  /// Nothing to do (no user signed in).
  ignored,
}

/// The result of opening a notification: what to do, and with which story.
typedef StoryLink = ({StoryLinkOutcome outcome, Story? story});

/// Turns push notifications into navigation for the signed-in home: a tap
/// (also the one that launched the app) is checked against the story's
/// current state, since it may have moved on since the notification was
/// sent. Notifications arriving in the foreground are offered as a banner
/// ([takeBanner]).
///
/// A mature story, complete or not, goes through the same age check as the
/// story lists ([MatureStoryAccess]), sharing their verdicts via [AgeGate]:
/// a known minor (session verdict or stored birth year) is told it's
/// unavailable without the check ever running. A story awaiting the AI
/// review can't be opened (see docs/PART_MODERATION_UI_SPEC.md §5 for the
/// order of the checks).
class NotificationRouterViewModel extends ChangeNotifier {
  NotificationRouterViewModel({
    required NotificationRepository notificationRepository,
    required StoryRepository storyRepository,
    required AuthRepository authRepository,
    required AgeGate ageGate,
  })  : _notifications = notificationRepository,
        _stories = storyRepository,
        _auth = authRepository,
        _access = MatureStoryAccess(
          ageGate: ageGate,
          authRepository: authRepository,
          // Nothing on screen follows the check's progress.
          onChanged: () {},
        ) {
    open = Command1<StoryLink, StoryNotification>(_open);
    submitBirthYear = Command1<StoryLink, int>(_submitBirthYear);
    _opened = _notifications.opened.listen(open.execute);
    _received = _notifications.received.listen(_onReceived);
    unawaited(_openLaunchNotification());
  }

  final NotificationRepository _notifications;
  final StoryRepository _stories;
  final AuthRepository _auth;
  final MatureStoryAccess _access;
  late final StreamSubscription<StoryNotification> _opened;
  late final StreamSubscription<StoryNotification> _received;

  bool _disposed = false;

  /// Works out where [StoryNotification] leads. Fails if the story can't be
  /// read (e.g. offline) or the age check fails.
  late final Command1<StoryLink, StoryNotification> open;

  /// Records the birth year entered for the story waiting on
  /// [StoryLinkOutcome.askBirthYear] and decides with it.
  late final Command1<StoryLink, int> submitBirthYear;

  /// The kind of the notification whose mature story waits for
  /// [submitBirthYear]: an adult then writes it or reads it.
  StoryNotificationKind? _awaitingKind;

  StoryNotification? _banner;

  /// The notification that arrived in the foreground, once: the View shows
  /// it and it's gone.
  StoryNotification? takeBanner() {
    final banner = _banner;
    _banner = null;
    return banner;
  }

  void _onReceived(StoryNotification notification) {
    _banner = notification;
    notifyListeners();
  }

  Future<void> _openLaunchNotification() async {
    final notification = await _notifications.takeLaunchNotification();
    if (notification != null && !_disposed) open.execute(notification);
  }

  Future<StoryLink> _open(StoryNotification notification) async {
    final email = _auth.currentEmail;
    if (email == null) return (outcome: StoryLinkOutcome.ignored, story: null);
    final story = await _stories.getStory(notification.storyId);
    if (story == null) return (outcome: StoryLinkOutcome.notFound, story: null);
    StoryLink link(StoryLinkOutcome outcome) =>
        (outcome: outcome, story: story);

    switch (notification.kind) {
      case StoryNotificationKind.continued:
        if (story.isComplete) return link(StoryLinkOutcome.alreadyCompleted);
        // Before "under review", as in the incomplete list: `mature` is
        // never downgraded, so a pending verdict can't change this answer.
        if (await _isKnownMinorFor(story)) {
          return link(StoryLinkOutcome.matureUnavailable);
        }
        if (story.awaitingReview) return link(StoryLinkOutcome.underReview);
        if (story.wasLastWrittenBy(email)) {
          return link(StoryLinkOutcome.alreadyContinued);
        }
        if (story.isLockedFor(email)) {
          return link(StoryLinkOutcome.lockedByOther);
        }
        if (story.mature == true && !_access.isSessionAdult) {
          return _unlock(story, notification.kind);
        }
        // Taking the lock is left to the chat screen, which handles losing
        // a race for it (or the story going into review meanwhile).
        return link(StoryLinkOutcome.write);
      case StoryNotificationKind.completed:
        if (!story.isComplete || story.awaitingReview) {
          return link(StoryLinkOutcome.notReadyYet);
        }
        if (story.mature != true || _access.isSessionAdult) {
          return link(StoryLinkOutcome.read);
        }
        if (await _isKnownMinorFor(story)) {
          return link(StoryLinkOutcome.matureUnavailable);
        }
        return _unlock(story, notification.kind);
    }
  }

  /// Whether [story] is mature and the user a known minor, reading the
  /// stored birth year quietly first (it may have been entered since the
  /// last tap). Never asks the platform.
  Future<bool> _isKnownMinorFor(Story story) async {
    if (story.mature != true) return false;
    await _access.loadBirthYear();
    return _access.isKnownMinor;
  }

  /// Runs the age check for the mature [story] of a [kind] notification.
  Future<StoryLink> _unlock(Story story, StoryNotificationKind kind) async {
    final result = await _access.unlock(story);
    if (result.outcome == UnlockOutcome.askBirthYear) _awaitingKind = kind;
    return _linkFor(result, kind);
  }

  /// Where an unlock [result] leads for a [kind] notification.
  StoryLink _linkFor(UnlockResult result, StoryNotificationKind kind) {
    final outcome = switch (result.outcome) {
      UnlockOutcome.open => kind == StoryNotificationKind.continued
          ? StoryLinkOutcome.write
          : StoryLinkOutcome.read,
      UnlockOutcome.minor => StoryLinkOutcome.matureUnavailable,
      UnlockOutcome.askBirthYear => StoryLinkOutcome.askBirthYear,
      UnlockOutcome.ignored => StoryLinkOutcome.ignored,
    };
    return (outcome: outcome, story: result.story);
  }

  Future<StoryLink> _submitBirthYear(int birthYear) async {
    final kind = _awaitingKind;
    _awaitingKind = null;
    if (kind == null || _access.awaitingBirthYear == null) {
      return (outcome: StoryLinkOutcome.ignored, story: null);
    }
    // Stored once and for all, like from the story lists.
    return _linkFor(await _access.submitBirthYear(birthYear), kind);
  }

  /// The user left the birth-year screen without answering.
  void cancelBirthYear() {
    _awaitingKind = null;
    _access.cancelBirthYear();
  }

  @override
  void dispose() {
    _disposed = true;
    _access.dispose();
    _opened.cancel();
    _received.cancel();
    open.dispose();
    submitBirthYear.dispose();
    super.dispose();
  }
}
