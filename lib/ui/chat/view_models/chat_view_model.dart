import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// State and actions of the chat screen, where the signed-in user writes the
/// next part of [story].
///
/// Takes the story's lock as soon as it is created ([lock]) and releases it
/// on [dispose] unless the part was submitted, so nobody else can write the
/// same turn meanwhile.
class ChatViewModel extends ChangeNotifier {
  ChatViewModel({
    required this.story,
    required StoryRepository storyRepository,
    required AuthRepository authRepository,
  })  : _stories = storyRepository,
        _auth = authRepository {
    lock = Command0<void>(_lock)..execute();
    submit = Command1<bool, String>(_submit);
  }

  final Story story;
  final StoryRepository _stories;
  final AuthRepository _auth;

  /// Takes the story's lock. Started by the constructor; fails with a
  /// [StoryException] if the story can't be written now.
  late final Command0<void> lock;

  /// Submits the text as the next part. Its value is true once the part is
  /// stored, false if there was nothing to send.
  late final Command1<bool, String> submit;

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
    return true;
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
    submit.dispose();
    super.dispose();
  }
}
