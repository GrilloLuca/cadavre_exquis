import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// Whether the signed-in user can open an incomplete story.
enum IncompleteStoryStatus {
  /// The user can write its next part.
  available,

  /// Someone else holds an unexpired lock on it.
  beingWritten,

  /// The user wrote the last part and must wait for someone else's turn.
  waitingForOthers,
}

/// The incomplete stories of the user's room, and creating new ones.
class IncompleteStoriesViewModel extends ChangeNotifier {
  /// [now] decides whether a lock has expired; tests pass a fixed clock.
  IncompleteStoriesViewModel({
    required StoryRepository storyRepository,
    required AuthRepository authRepository,
    required String language,
    String? roomId,
    DateTime Function()? now,
  })  : _stories = storyRepository,
        _auth = authRepository,
        _now = now ?? DateTime.now,
        _language = language,
        _roomId = roomId {
    createStory = Command0<Story>(_createStory);
    _subscribe();
  }

  final StoryRepository _stories;
  final AuthRepository _auth;
  final DateTime Function() _now;

  String _language;
  String? _roomId;
  StreamSubscription<List<Story>>? _subscription;

  /// Creates an empty story in the room; its value is the new story, to
  /// open straight away.
  late final Command0<Story> createStory;

  List<Story>? _list;

  /// The room's incomplete stories, least written first. Null until the
  /// first list arrives.
  List<Story>? get stories => _list;

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

  /// What the signed-in user can do with [story] right now. Computed on
  /// each call, so an expired lock frees the story on the next rebuild.
  IncompleteStoryStatus statusOf(Story story) {
    final email = _auth.currentEmail;
    if (story.isLockedFor(email, now: _now())) {
      return IncompleteStoryStatus.beingWritten;
    }
    if (story.wasLastWrittenBy(email)) {
      return IncompleteStoryStatus.waitingForOthers;
    }
    return IncompleteStoryStatus.available;
  }

  Future<Story> _createStory() =>
      _stories.createStory(language: _language, roomId: _roomId);

  @override
  void dispose() {
    _subscription?.cancel();
    createStory.dispose();
    super.dispose();
  }
}
