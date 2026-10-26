import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/ads/ads_repository.dart';
import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/notification/notification_repository.dart';
import 'package:cadavre_exquisite/data/repositories/room/room_repository.dart';
import 'package:cadavre_exquisite/data/repositories/safety/safety_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/domain/models/author_name.dart';
import 'package:cadavre_exquisite/domain/models/nickname.dart';
import 'package:cadavre_exquisite/domain/models/private_room.dart';
import 'package:cadavre_exquisite/domain/models/story_language.dart';
import 'package:cadavre_exquisite/domain/models/story_notification.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// The profile tab: the user's nickname, their room, push notifications, ad
/// privacy, the players they blocked, signing out and deleting the account.
class AccountViewModel extends ChangeNotifier {
  /// Starts loading the nickname when someone is signed in.
  AccountViewModel({
    required UserProfileRepository profileRepository,
    required AuthRepository authRepository,
    required RoomRepository roomRepository,
    required NotificationRepository notificationRepository,
    required AdsRepository adsRepository,
    required SafetyRepository safetyRepository,
  })  : _profiles = profileRepository,
        _safety = safetyRepository,
        _auth = authRepository,
        _rooms = roomRepository,
        _notifications = notificationRepository,
        _ads = adsRepository,
        email = authRepository.currentEmail {
    loadNickname = Command0<String?>(_loadNickname);
    saveNickname = Command1<void, String>(_saveNickname);
    deleteAccount = Command1<bool, String?>(_deleteAccount);
    signOut = Command0<void>(_signOut);
    enableNotifications =
        Command0<NotificationPermission>(_notifications.enable);
    showAdPrivacyOptions = Command0<void>(_ads.showPrivacyOptions);
    unblock = Command1<void, String>(_safety.unblock);
    _rooms.addListener(notifyListeners);
    _safety.addListener(_onBlockedChanged);
    _loadBlockedNicknames();
    _notifications.addListener(notifyListeners);
    _ads.addListener(notifyListeners);
    if (email != null) loadNickname.execute();
  }

  final UserProfileRepository _profiles;
  final AuthRepository _auth;
  final RoomRepository _rooms;
  final NotificationRepository _notifications;
  final AdsRepository _ads;
  final SafetyRepository _safety;

  /// The signed-in user, read once: signing out leaves this screen. Without
  /// one there is no nickname to show and no account to delete.
  final String? email;

  // ---- Nickname ----

  /// Fetches the stored nickname; its value is the nickname, or null if
  /// none is set. While it runs, or after it failed, the form is disabled:
  /// the user may already have a nickname. Run it again to retry.
  late final Command0<String?> loadNickname;

  /// Stores the given (normalized) nickname. Fails with a
  /// [UserProfileException]; on [UserProfileErrorCode.nicknameAlreadySet]
  /// (set meanwhile, e.g. on another device) the stored one is reloaded.
  late final Command1<void, String> saveNickname;

  /// The stored nickname, null until loaded or if none is set.
  String? _nickname;

  /// Whether a nickname is stored: it can be chosen only once, so the field
  /// becomes read-only.
  bool get hasNickname => _nickname != null;

  /// The stored nickname, once known.
  String? get nickname => _nickname;

  /// Whether the last load failed; the form stays disabled until a retry
  /// succeeds.
  bool get nicknameLoadFailed => loadNickname.error != null;

  /// Whether the nickname can't be edited or saved right now.
  bool get isNicknameBusy =>
      loadNickname.running || saveNickname.running || nicknameLoadFailed;

  /// Whether the user may type and save a nickname.
  bool get canEditNickname => !isNicknameBusy && !hasNickname;

  Future<String?> _loadNickname() async {
    _nickname = await _profiles.getNickname(email!);
    return _nickname;
  }

  Future<void> _saveNickname(String normalized) async {
    try {
      await _profiles.setNickname(email: email!, nickname: normalized);
      _nickname = normalized;
    } on UserProfileException catch (e) {
      if (e.code == UserProfileErrorCode.nicknameAlreadySet) {
        loadNickname.execute();
      }
      rethrow;
    }
  }

  /// The name other players will see for [typed]: the nickname if it's
  /// valid, otherwise the masked email; null if neither is usable.
  String? publicName(String typed) {
    final isValid = Nickname.validate(typed) == null;
    return authorDisplayName(
      nickname: isValid ? Nickname.normalize(typed) : null,
      email: email,
    );
  }

  // ---- Room ----

  /// The language room the user is in, or returns to when they leave the
  /// private room.
  String get languageCode => _rooms.languageCode ?? kFallbackRoomLanguage;

  /// How [languageCode] was picked; anything but an explicit choice is
  /// explained with a caption.
  RoomLanguageSource get languageSource => _rooms.languageSource;

  /// The private room the user is in, or null.
  PrivateRoom? get privateRoom => _rooms.privateRoom;

  /// Picks a language room, which also leaves the private room.
  void selectLanguage(String code) => _rooms.selectLanguage(code);

  void enterPrivateRoom(PrivateRoom room) => _rooms.enterPrivateRoom(room);

  void leavePrivateRoom() => _rooms.leavePrivateRoom();

  // ---- Notifications ----

  /// Whether the device shows push notifications, null until known. The
  /// card is hidden while unknown and where push doesn't exist.
  NotificationPermission? get notificationPermission =>
      _notifications.permission;

  /// Asks for the permission (the system prompt) and registers the device.
  late final Command0<NotificationPermission> enableNotifications;

  // ---- Ads ----

  /// Whether to offer changing the ad consent: required by GDPR in the
  /// EEA/UK, where the user must be able to do it at any time.
  bool get adPrivacyOptionsRequired => _ads.privacyOptionsRequired;

  /// Shows the ad consent form again.
  late final Command0<void> showAdPrivacyOptions;

  // ---- Blocked players ----

  /// The email keys of the players the user blocked, in a stable order.
  List<String> get blockedKeys => _safety.blockedKeys.toList()..sort();

  /// Nicknames of the blocked players, by email key, as far as loaded.
  final Map<String, String> _blockedNicknames = {};

  /// The name to show for the blocked player [key]: their nickname once
  /// loaded, otherwise the masked email.
  String blockedNameOf(String key) =>
      authorDisplayName(nickname: _blockedNicknames[key], email: key) ?? key;

  /// Unblocks the player with the given email key.
  late final Command1<void, String> unblock;

  bool _disposed = false;

  void _onBlockedChanged() {
    notifyListeners();
    _loadBlockedNicknames();
  }

  /// Looks up the nicknames not loaded yet. Never fails: without one the
  /// masked email is shown.
  Future<void> _loadBlockedNicknames() async {
    final missing = _safety.blockedKeys
        .where((key) => !_blockedNicknames.containsKey(key))
        .toList();
    if (missing.isEmpty) return;
    try {
      final found = await _profiles.nicknamesFor(missing);
      if (_disposed || found.isEmpty) return;
      _blockedNicknames.addAll(found);
      notifyListeners();
    } catch (_) {}
  }

  // ---- Account ----

  /// Whether the user signs in with a password, which they must enter again
  /// to delete the account; otherwise they pick their Google account again.
  bool get usesPassword => _auth.usesPassword;

  /// Confirms the user's identity with the given password (null for Google
  /// users), then deletes the account. Its value is false if the user
  /// dismissed the Google account picker. Fails with an [AuthException]
  /// (e.g. a wrong password).
  late final Command1<bool, String?> deleteAccount;

  /// Signs out. `AgeGate` and `RoomRepository` forget the session by
  /// themselves; the device stops getting this user's notifications first,
  /// while the user can still remove its token.
  late final Command0<void> signOut;

  Future<void> _signOut() async {
    await _notifications.unregister();
    await _auth.signOut();
  }

  Future<bool> _deleteAccount(String? password) async {
    final confirmed = await _auth.reauthenticate(password: password);
    if (!confirmed) return false;
    // The anonymizeDeletedUser Cloud Function deletes the profile: the
    // rules don't let the user delete it, as that would free the nickname
    // to be chosen again. It deletes the push tokens too; this device's is
    // removed here as well, so it stops right away.
    await _notifications.unregister();
    await _auth.deleteAccount();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _safety.removeListener(_onBlockedChanged);
    unblock.dispose();
    _rooms.removeListener(notifyListeners);
    _notifications.removeListener(notifyListeners);
    _ads.removeListener(notifyListeners);
    enableNotifications.dispose();
    showAdPrivacyOptions.dispose();
    loadNickname.dispose();
    saveNickname.dispose();
    deleteAccount.dispose();
    signOut.dispose();
    super.dispose();
  }
}
