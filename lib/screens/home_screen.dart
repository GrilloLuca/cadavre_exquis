import 'package:flutter/material.dart';
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

  static const _titles = ['Storie incomplete', 'Storie complete', 'Profilo'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(_titles[_selectedIndex]),
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
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.edit_note),
            label: 'Incomplete',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book),
            label: 'Complete',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profilo',
          ),
        ],
      ),
    );
  }
}
