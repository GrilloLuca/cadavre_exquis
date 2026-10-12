import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/domain/models/private_room.dart';
import 'package:cadavre_exquisite/domain/models/story_language.dart';
import 'package:cadavre_exquisite/screens/account_screen.dart';
import 'package:cadavre_exquisite/screens/complete_stories_screen.dart';
import 'package:cadavre_exquisite/ui/incomplete_stories/widgets/incomplete_stories_screen.dart';
import 'package:cadavre_exquisite/services/language_room_preference.dart';

class HomeScreen extends StatefulWidget {
  static String id = 'home_screen';

  const HomeScreen({super.key, this.languageRoomPreference});

  /// Where the language room choice is read from and saved to. Defaults to
  /// a [LanguageRoomPreference] backed by the device's shared preferences.
  final LanguageRoomPreference? languageRoomPreference;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _profileTabIndex = 2;

  late final LanguageRoomPreference _preference;

  int _selectedIndex = 0;

  /// Null until the stored/detected room is resolved, so the story tabs
  /// build their first query for the right room only.
  String? _languageCode;
  RoomLanguageSource _languageSource = RoomLanguageSource.explicit;

  /// Kept in memory only: a restart (or sign-out) puts the user back in
  /// their language room.
  PrivateRoom? _privateRoom;

  @override
  void initState() {
    super.initState();
    _preference = widget.languageRoomPreference ?? LanguageRoomPreference();
    _resolveLanguage();
  }

  Future<void> _resolveLanguage() async {
    ({String code, RoomLanguageSource source}) resolved;
    try {
      resolved = await _preference.resolveWithSource();
    } catch (_) {
      // Unreadable storage: behave as if nothing were stored.
      resolved = detectRoomLanguageWithSource(
        WidgetsBinding.instance.platformDispatcher.locales,
      );
    }
    if (!mounted) return;
    setState(() {
      _languageCode = resolved.code;
      _languageSource = resolved.source;
    });
  }

  /// Switches to the [code] language room, leaving any private room, and
  /// remembers it as the user's explicit choice.
  Future<void> _selectLanguage(String code) async {
    setState(() {
      _languageCode = code;
      _languageSource = RoomLanguageSource.explicit;
      _privateRoom = null;
    });
    try {
      await _preference.saveExplicit(code);
    } catch (_) {
      // Keep the choice for this session only.
    }
  }

  void _setPrivateRoom(PrivateRoom? room) {
    setState(() => _privateRoom = room);
  }

  Widget _buildRoomIndicator(
    BuildContext context,
    AppLocalizations l10n,
    StoryLanguage language,
  ) {
    final privateRoom = _privateRoom;
    final label = privateRoom != null
        ? l10n.roomIndicatorPrivate(privateRoom.name)
        : l10n.roomIndicatorLanguage(language.nativeName);
    // Below 360dp there is no room for the name next to the title.
    final showName = MediaQuery.sizeOf(context).width >= 360.0;

    final Widget content;
    if (privateRoom == null) {
      content = Text(language.flag, style: const TextStyle(fontSize: 20.0));
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircleAvatar(
            radius: 14.0,
            backgroundColor: AppColors.cream,
            child: Icon(Icons.lock, color: AppColors.primary, size: 18.0),
          ),
          if (showName) ...[
            const SizedBox(width: 6.0),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120.0),
              child: Text(
                privateRoom.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // The AppBar has a fixed height; the full name is in the
                // tooltip and semantics label.
                textScaler: MediaQuery.textScalerOf(context)
                    .clamp(maxScaleFactor: 1.3),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 4.0),
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => setState(() => _selectedIndex = _profileTabIndex),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(minWidth: 48.0, minHeight: 48.0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Center(widthFactor: 1.0, child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final languageCode = _languageCode;
    final language =
        languageCode == null ? null : storyLanguageByCode(languageCode);
    final privateRoom = _privateRoom;
    final titles = [
      l10n.titleIncompleteStories,
      l10n.titleCompleteStories,
      l10n.titleProfile,
    ];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(titles[_selectedIndex]),
        backgroundColor: AppColors.primary,
        actions: [
          if (language != null && _selectedIndex != _profileTabIndex)
            _buildRoomIndicator(context, l10n, language),
        ],
      ),
      body: language == null
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _selectedIndex,
              children: <Widget>[
                IncompleteStoriesScreen(
                  language: language.code,
                  roomId: privateRoom?.id,
                ),
                CompleteStoriesScreen(
                  language: language.code,
                  roomId: privateRoom?.id,
                ),
                AccountScreen(
                  languageCode: language.code,
                  languageSource: _languageSource,
                  privateRoom: privateRoom,
                  onLanguageChanged: _selectLanguage,
                  onPrivateRoomChanged: _setPrivateRoom,
                ),
              ],
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: const Icon(Icons.edit_note),
            label: l10n.homeTabIncomplete,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.menu_book),
            label: l10n.homeTabComplete,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: l10n.homeTabProfile,
          ),
        ],
      ),
    );
  }
}
