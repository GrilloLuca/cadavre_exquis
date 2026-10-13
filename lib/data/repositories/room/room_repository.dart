import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/domain/models/private_room.dart';
import 'package:cadavre_exquisite/domain/models/story_language.dart';

/// The room the user plays in: a public language room, or a private room
/// that takes precedence over it while the user is in it. Notifies
/// listeners on every change.
abstract class RoomRepository extends ChangeNotifier {
  /// Code of the language room, null until [load] has resolved it.
  String? get languageCode;

  /// How [languageCode] was picked.
  RoomLanguageSource get languageSource;

  /// The private room the user is in, or null. Kept in memory only: a
  /// restart or a sign-out puts the user back in their language room.
  PrivateRoom? get privateRoom;

  /// Resolves the language room (stored choice, else detected from the
  /// device). Safe to call more than once; never fails.
  Future<void> load();

  /// Switches to the [code] language room as the user's explicit choice,
  /// leaving the private room, if any.
  Future<void> selectLanguage(String code);

  void enterPrivateRoom(PrivateRoom room);

  void leavePrivateRoom();
}
