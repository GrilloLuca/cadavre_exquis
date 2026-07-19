import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/models/story_language.dart';
import 'package:cadavre_exquisite/screens/account_screen.dart';
import 'package:cadavre_exquisite/screens/complete_stories_screen.dart';
import 'package:cadavre_exquisite/screens/incomplete_stories_screen.dart';

class HomeScreen extends StatefulWidget {
  static String id = 'home_screen';

  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String? _languageCode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Join the room matching the device language by default; fall back to
    // the first supported language if it isn't available as a room.
    _languageCode ??= storyLanguageByCode(
      Localizations.localeOf(context).languageCode,
    ).code;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final language = storyLanguageByCode(_languageCode!);
    final titles = [
      l10n.titleIncompleteStories,
      l10n.titleCompleteStories,
      l10n.titleProfile,
    ];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(titles[_selectedIndex]),
        backgroundColor: Colors.lightBlueAccent,
        actions: [
          if (_selectedIndex != 2)
            PopupMenuButton<String>(
              tooltip: l10n.languageRoomTooltip,
              initialValue: language.code,
              onSelected: (code) => setState(() => _languageCode = code),
              itemBuilder: (context) => [
                for (final lang in kStoryLanguages)
                  PopupMenuItem(
                    value: lang.code,
                    child: Text('${lang.flag}  ${lang.nativeName}'),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Text(
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
          IncompleteStoriesScreen(language: language.code),
          CompleteStoriesScreen(language: language.code),
          const AccountScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.lightBlueAccent,
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
