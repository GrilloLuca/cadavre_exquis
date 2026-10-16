import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/ads/ads_repository.dart';
import 'package:cadavre_exquisite/data/repositories/room/room_repository.dart';
import 'package:cadavre_exquisite/domain/models/private_room.dart';
import 'package:cadavre_exquisite/domain/models/story_language.dart';

/// The room the home screen's tabs show. Starts resolving the language
/// room on creation.
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required RoomRepository roomRepository,
    required AdsRepository adsRepository,
  })  : _rooms = roomRepository,
        _ads = adsRepository {
    _rooms.addListener(notifyListeners);
    _rooms.load();
  }

  final RoomRepository _rooms;
  final AdsRepository _ads;

  /// Asks for ad consent (the consent form, where required) and starts the
  /// ads SDK, once the user is in. Never fails: ads simply stay off.
  void startAds() => _ads.initialize();

  /// The language room, null until resolved: the story tabs wait for it so
  /// they only query the right room.
  StoryLanguage? get language {
    final code = _rooms.languageCode;
    return code == null ? null : storyLanguageByCode(code);
  }

  /// The private room the user is in, which takes precedence over
  /// [language], or null.
  PrivateRoom? get privateRoom => _rooms.privateRoom;

  @override
  void dispose() {
    _rooms.removeListener(notifyListeners);
    super.dispose();
  }
}
