import 'package:cadavre_exquisite/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/models/private_room.dart';
import 'package:cadavre_exquisite/models/story_language.dart';
import 'package:cadavre_exquisite/screens/account_screen.dart';
import 'package:cadavre_exquisite/screens/complete_stories_screen.dart';
import 'package:cadavre_exquisite/screens/incomplete_stories_screen.dart';
import 'package:cadavre_exquisite/screens/private_room_screen.dart';

class HomeScreen extends StatefulWidget {
  static String id = 'home_screen';

  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Sentinel values for the room-picker menu, distinct from any language
  // code, used to trigger the private-room flow instead of switching rooms.
  static const _privateRoomMenuValue = '__private_room__';
  static const _leavePrivateRoomMenuValue = '__leave_private_room__';

  int _selectedIndex = 0;
  String? _languageCode;
  PrivateRoom? _privateRoom;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Join the room matching the device language by default; fall back to
    // the first supported language if it isn't available as a room.
    _languageCode ??= storyLanguageByCode(
      Localizations.localeOf(context).languageCode,
    ).code;
  }

  Future<void> _openPrivateRoomPicker() async {
    final room = await Navigator.push<PrivateRoom>(
      context,
      MaterialPageRoute(builder: (_) => const PrivateRoomScreen()),
    );
    if (room != null && mounted) {
      setState(() => _privateRoom = room);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final language = storyLanguageByCode(_languageCode!);
    final privateRoom = _privateRoom;
    final titles = [
      l10n.titleIncompleteStories,
      l10n.titleCompleteStories,
      l10n.titleProfile,
    ];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          privateRoom != null
              ? '${titles[_selectedIndex]} · ${privateRoom.name}'
              : titles[_selectedIndex],
        ),
        backgroundColor: AppColors.primary,
        actions: [
          if (_selectedIndex != 2)
            PopupMenuButton<String>(
              tooltip: l10n.languageRoomTooltip,
              initialValue: language.code,
              onSelected: (value) {
                if (value == _privateRoomMenuValue) {
                  _openPrivateRoomPicker();
                } else if (value == _leavePrivateRoomMenuValue) {
                  setState(() => _privateRoom = null);
                } else {
                  setState(() {
                    _privateRoom = null;
                    _languageCode = value;
                  });
                }
              },
              itemBuilder: (context) => [
                for (final lang in kStoryLanguages)
                  PopupMenuItem(
                    value: lang.code,
                    child: Text('${lang.flag}  ${lang.nativeName}'),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _privateRoomMenuValue,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline, size: 20.0),
                      const SizedBox(width: 8.0),
                      Text(l10n.privateRoomMenuItem),
                    ],
                  ),
                ),
                if (privateRoom != null)
                  PopupMenuItem(
                    value: _leavePrivateRoomMenuValue,
                    child: Text(l10n.leavePrivateRoomMenuItem),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    privateRoom != null
                        ? const Icon(Icons.lock, color: Colors.white, size: 20.0)
                        : Text(
                            language.flag,
                            style: const TextStyle(fontSize: 20.0),
                          ),
                    const Icon(Icons.arrow_drop_down, color: Colors.white),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: IndexedStack(
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
          const AccountScreen(),
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
