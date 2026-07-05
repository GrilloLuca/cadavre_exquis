import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: const <Widget>[
          IncompleteStoriesScreen(),
          CompleteStoriesScreen(),
          AccountScreen(),
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
