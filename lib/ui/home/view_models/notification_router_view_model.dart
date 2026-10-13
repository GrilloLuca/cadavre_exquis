import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/notification/notification_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/models/story_notification.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
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
/// A mature story goes through the same age check as the complete stories
/// list (see `CompleteStoriesViewModel`), sharing its verdicts via
/// [AgeGate].
class NotificationRouterViewModel extends ChangeNotifier {
  NotificationRouterViewModel({
    required NotificationRepository notificationRepository,
    required StoryRepository storyRepository,
    required AuthRepository authRepository,
    required AgeGate ageGate,
  })  : _notifications = notificationRepository,
        _stories = storyRepository,
        _auth = authRepository,
        _gate = ageGate {
    open = Command1<StoryLink, StoryNotification>(_open);
    submitBirthYear = Command1<StoryLink, int>(_submitBirthYear);
    _opened = _notifications.opened.listen(open.execute);
    _received = _notifications.received.listen(_onReceived);
    unawaited(_openLaunchNotification());
  }

  final NotificationRepository _notifications;
  final StoryRepository _stories;
  final AuthRepository _auth;
  final AgeGate _gate;
  late final StreamSubscription<StoryNotification> _opened;
  late final StreamSubscription<StoryNotification> _received;

  bool _disposed = false;

  /// Works out where [StoryNotification] leads. Fails if the story can't be
  /// read (e.g. offline) or the age check fails.
  late final Command1<StoryLink, StoryNotification> open;

  /// Records the birth year entered for the story waiting on
  /// [StoryLinkOutcome.askBirthYear] and decides with it.
  late final Command1<StoryLink, int> submitBirthYear;

  /// The mature story waiting for [submitBirthYear].
  Story? _awaitingBirthYear;

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

    switch (notification.kind) {
      case StoryNotificationKind.continued:
        final StoryLinkOutcome outcome;
        if (story.isComplete) {
          outcome = StoryLinkOutcome.alreadyCompleted;
        } else if (story.wasLastWrittenBy(email)) {
          outcome = StoryLinkOutcome.alreadyContinued;
        } else if (story.isLockedFor(email)) {
          outcome = StoryLinkOutcome.lockedByOther;
        } else {
          // Taking the lock is left to the chat screen, which handles losing
          // a race for it.
          outcome = StoryLinkOutcome.write;
        }
        return (outcome: outcome, story: story);
      case StoryNotificationKind.completed:
        if (!story.isComplete || story.mature == null) {
          return (outcome: StoryLinkOutcome.notReadyYet, story: story);
        }
        if (story.mature != true || _gate.isSessionAdult(email)) {
          return (outcome: StoryLinkOutcome.read, story: story);
        }
        if (_gate.isSessionMinor(email)) {
          return (outcome: StoryLinkOutcome.matureUnavailable, story: story);
        }
        switch (await _gate.resolve(email)) {
          case AgeVerdict.adult:
            _gate.rememberVerdict(email, adult: true);
            return (outcome: StoryLinkOutcome.read, story: story);
          case AgeVerdict.minor:
            _gate.rememberVerdict(email, adult: false);
            return (outcome: StoryLinkOutcome.matureUnavailable, story: story);
          case AgeVerdict.askBirthYear:
            _awaitingBirthYear = story;
            return (outcome: StoryLinkOutcome.askBirthYear, story: story);
        }
    }
  }

  Future<StoryLink> _submitBirthYear(int birthYear) async {
    final email = _auth.currentEmail;
    final story = _awaitingBirthYear;
    _awaitingBirthYear = null;
    if (email == null || story == null) {
      return (outcome: StoryLinkOutcome.ignored, story: null);
    }
    // Stored once and for all, like from the complete stories list.
    final adult = await _gate.recordBirthYear(email, birthYear);
    _gate.rememberVerdict(email, adult: adult);
    return (
      outcome:
          adult ? StoryLinkOutcome.read : StoryLinkOutcome.matureUnavailable,
      story: story,
    );
  }

  /// The user left the birth-year screen without answering.
  void cancelBirthYear() => _awaitingBirthYear = null;

  @override
  void dispose() {
    _disposed = true;
    _opened.cancel();
    _received.cancel();
    open.dispose();
    submitBirthYear.dispose();
    super.dispose();
  }
}
