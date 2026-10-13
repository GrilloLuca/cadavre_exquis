import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/domain/models/story_language.dart';
import 'package:cadavre_exquisite/ui/account/widgets/account_screen.dart';
import 'package:cadavre_exquisite/ui/complete_stories/widgets/complete_stories_screen.dart';
import 'package:cadavre_exquisite/ui/incomplete_stories/widgets/incomplete_stories_screen.dart';
import 'package:cadavre_exquisite/data/repositories/room/room_repository.dart';
import 'package:cadavre_exquisite/ui/home/view_models/home_view_model.dart';

/// The signed-in home: incomplete stories, complete stories and profile
/// tabs for the current room. Creates its [HomeViewModel] once, in
/// `initState` (see `ChatScreen`).
class HomeScreen extends StatefulWidget {
  static String id = 'home_screen';

  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _profileTabIndex = 2;

  late final HomeViewModel _viewModel;

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _viewModel =
        HomeViewModel(roomRepository: context.read<RoomRepository>());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Widget _buildRoomIndicator(
    BuildContext context,
    AppLocalizations l10n,
    StoryLanguage language,
  ) {
    final privateRoom = _viewModel.privateRoom;
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
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final language = _viewModel.language;
    final privateRoom = _viewModel.privateRoom;
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
