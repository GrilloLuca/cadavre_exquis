import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/notification/notification_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/domain/models/author_name.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// State and actions of the chat screen, where the signed-in user writes the
/// next part of [story].
///
/// Takes the story's lock as soon as it is created ([lock]) and releases it
/// on [dispose] unless the part was submitted, so nobody else can write the
/// same turn meanwhile.
///
/// After a part is sent it may offer to turn on push notifications
/// ([offerNotifications]), when the user has never been asked: that's when
/// knowing someone continued the story is obviously useful.
///
/// Also looks up the nickname of whoever wrote the previous part
/// ([loadPreviousAuthor]), shown above its last words.
class ChatViewModel extends ChangeNotifier {
  ChatViewModel({
    required this.story,
    required StoryRepository storyRepository,
    required AuthRepository authRepository,
    required NotificationRepository notificationRepository,
    required UserProfileRepository profileRepository,
  })  : _stories = storyRepository,
        _auth = authRepository,
        _notifications = notificationRepository,
        _profiles = profileRepository {
    lock = Command0<void>(_lock)..execute();
    loadPreviousAuthor = Command0<void>(_loadPreviousAuthor)..execute();
    submit = Command1<bool, String>(_submit);
    answerNotificationOffer = Command1<void, bool>(_answerNotificationOffer);
  }

  final Story story;
  final StoryRepository _stories;
  final AuthRepository _auth;
  final NotificationRepository _notifications;
  final UserProfileRepository _profiles;

  /// Takes the story's lock. Started by the constructor; fails with a
  /// [StoryException] if the story can't be written now.
  late final Command0<void> lock;

  /// Fetches the previous part's author's nickname. Started by the
  /// constructor; never fails: without it the masked email is shown.
  late final Command0<void> loadPreviousAuthor;

  /// Submits the text as the next part. Its value is true once the part is
  /// stored, false if there was nothing to send.
  late final Command1<bool, String> submit;

  /// Turns notifications on (true: the system prompt follows) or puts the
  /// offer off (false). Never fails.
  late final Command1<void, bool> answerNotificationOffer;

  String? _previousAuthorNickname;

  /// The last part written so far, null for a story without parts.
  StoryPart? get previousPart => story.parts.isEmpty ? null : story.parts.last;

  /// The name to show for [previousPart]'s author: their nickname once
  /// loaded, otherwise the masked email; null if neither is usable.
  String? get previousAuthorName {
    final part = previousPart;
    if (part == null) return null;
    return authorDisplayName(
        nickname: _previousAuthorNickname, email: part.author);
  }

  bool _offerNotifications = false;

  /// Whether to offer turning on notifications, once [submit] succeeded.
  bool get offerNotifications => _offerNotifications;

  /// Email the lock is held for, null when no lock is held.
  String? _lockHolder;

  bool _disposed = false;

  /// Whether the user can write: the lock is held and nothing is being sent.
  bool get canWrite => _lockHolder != null && !submit.running;

  Future<void> _lock() async {
    final email = _auth.currentEmail;
    if (email == null) return;
    await _stories.lockStory(storyId: story.id, authorEmail: email);
    if (_disposed) {
      // The screen closed while locking: give the turn back straight away.
      _unlock(email);
      return;
    }
    _lockHolder = email;
    notifyListeners();
  }

  Future<void> _loadPreviousAuthor() async {
    final part = previousPart;
    if (part == null) return;
    try {
      _previousAuthorNickname = await _profiles.getNickname(part.author);
    } catch (_) {
      _previousAuthorNickname = null;
    }
  }

  Future<bool> _submit(String text) async {
    final trimmed = text.trim();
    final email = _lockHolder;
    if (trimmed.isEmpty || email == null) return false;

    await _stories.submitPart(
      storyId: story.id,
      expectedPosition: story.currentPosition,
      text: trimmed,
      authorEmail: email,
    );
    // Submitting releases the lock.
    _lockHolder = null;
    try {
      _offerNotifications = await _notifications.shouldOffer();
    } catch (_) {
      // The part is sent: never report a failure here.
    }
    return true;
  }

  Future<void> _answerNotificationOffer(bool accepted) async {
    _offerNotifications = false;
    try {
      if (accepted) {
        await _notifications.enable();
      } else {
        await _notifications.dismissOffer();
      }
    } catch (_) {
      // The part is sent either way; the profile tab can turn them on.
    }
  }

  /// Fire and forget: dispose can't wait. A failure (e.g. offline) must not
  /// surface as an uncaught async error; the lock stays until it expires or
  /// the next unlock attempt.
  void _unlock(String email) {
    unawaited(_stories
        .unlockStory(storyId: story.id, authorEmail: email)
        .catchError((Object _) {}));
  }

  @override
  void dispose() {
    _disposed = true;
    final email = _lockHolder;
    if (email != null) _unlock(email);
    lock.dispose();
    loadPreviousAuthor.dispose();
    submit.dispose();
    answerNotificationOffer.dispose();
    super.dispose();
  }
}
