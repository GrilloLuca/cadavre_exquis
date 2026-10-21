import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/domain/models/story_language.dart';
import 'package:cadavre_exquisite/ui/account/widgets/account_screen.dart';
import 'package:cadavre_exquisite/ui/complete_stories/widgets/complete_stories_screen.dart';
import 'package:cadavre_exquisite/ui/incomplete_stories/widgets/incomplete_stories_screen.dart';
import 'package:cadavre_exquisite/data/repositories/ads/ads_repository.dart';
import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/notification/notification_repository.dart';
import 'package:cadavre_exquisite/data/repositories/room/room_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/domain/models/ad_placement.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/ui/chat/widgets/chat_screen.dart';
import 'package:cadavre_exquisite/ui/complete_stories/widgets/age_check_screen.dart';
import 'package:cadavre_exquisite/ui/core/ui/ad_banner.dart';
import 'package:cadavre_exquisite/ui/home/view_models/home_view_model.dart';
import 'package:cadavre_exquisite/ui/home/view_models/notification_router_view_model.dart';
import 'package:cadavre_exquisite/ui/story_read/widgets/story_read_screen.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// The signed-in home: incomplete stories, complete stories and profile
/// tabs for the current room. Also opens the stories of tapped push
/// notifications, since it only exists while someone is signed in. Creates
/// its [HomeViewModel] and [NotificationRouterViewModel] once, in
/// `initState` (see `ChatScreen`).
class HomeScreen extends StatefulWidget {
  static String id = 'home_screen';

  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _completeTabIndex = 1;
  static const int _profileTabIndex = 2;

  late final HomeViewModel _viewModel;
  late final NotificationRouterViewModel _router;

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _viewModel = HomeViewModel(
      roomRepository: context.read<RoomRepository>(),
      adsRepository: context.read<AdsRepository>(),
    );
    // Consent and the ads SDK start once the home is on screen, without
    // delaying it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _viewModel.startAds();
    });
    _router = NotificationRouterViewModel(
      notificationRepository: context.read<NotificationRepository>(),
      storyRepository: context.read<StoryRepository>(),
      authRepository: context.read<AuthRepository>(),
      ageGate: context.read<AgeGate>(),
    );
    _router.addListener(_onRouterChanged);
    _router.open.addListener(_onOpenChanged);
    _router.submitBirthYear.addListener(_onSubmitBirthYearChanged);
  }

  @override
  void dispose() {
    _router.removeListener(_onRouterChanged);
    _router.open.removeListener(_onOpenChanged);
    _router.submitBirthYear.removeListener(_onSubmitBirthYearChanged);
    _router.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _showSnackBar(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  /// A notification arrived while the app is open: the system doesn't show
  /// it, so it's offered here.
  void _onRouterChanged() {
    final notification = _router.takeBanner();
    if (notification == null) return;
    final l10n = AppLocalizations.of(context)!;
    final text = notification.title ?? notification.body;
    if (text == null) return;
    _showSnackBar(
      text,
      action: SnackBarAction(
        label: l10n.notificationOpenAction,
        onPressed: () => _router.open.execute(notification),
      ),
    );
  }

  void _onOpenChanged() => _handleLink(_router.open);

  void _onSubmitBirthYearChanged() => _handleLink(_router.submitBirthYear);

  /// Opens the story of a tapped notification, or says why it can't.
  Future<void> _handleLink(Command<StoryLink> command) async {
    if (command.running) return;
    final l10n = AppLocalizations.of(context)!;
    if (command.error != null) {
      command.clearResult();
      _showSnackBar(l10n.genericError);
      return;
    }
    final link = command.value;
    if (!command.completed || link == null) return;
    command.clearResult();
    final story = link.story;
    switch (link.outcome) {
      case StoryLinkOutcome.write:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChatScreen(story: story!)),
        );
      case StoryLinkOutcome.read:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => StoryReadScreen(story: story!)),
        );
      case StoryLinkOutcome.askBirthYear:
        final birthYear = await Navigator.push<int>(
          context,
          MaterialPageRoute(builder: (_) => const AgeCheckScreen()),
        );
        if (!mounted) return;
        if (birthYear == null) {
          _router.cancelBirthYear();
        } else {
          _router.submitBirthYear.execute(birthYear);
        }
      case StoryLinkOutcome.matureUnavailable:
        _showSnackBar(l10n.matureStoryUnavailable);
      case StoryLinkOutcome.notFound:
        _showSnackBar(l10n.storyNotFound);
      case StoryLinkOutcome.notReadyYet:
        _showSnackBar(l10n.storyNotReadyYet);
      case StoryLinkOutcome.alreadyCompleted:
        _showSnackBar(l10n.errorStoryAlreadyCompleted);
      case StoryLinkOutcome.lockedByOther:
        _showSnackBar(l10n.errorStoryLockedByOther);
      case StoryLinkOutcome.alreadyContinued:
        _showSnackBar(l10n.errorConsecutiveTurnNotAllowed);
      case StoryLinkOutcome.ignored:
        break;
    }
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
                textScaler:
                    MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
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
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The banner lives here rather than in CompleteStoriesScreen: the
          // IndexedStack keeps every tab alive, so it would keep loading ads
          // while hidden. Built only on the complete-stories tab.
          if (_selectedIndex == _completeTabIndex)
            // The navigation bar below already pads for the bottom inset.
            MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: const AdBanner(
                placement: AdPlacement.completeStoriesBanner,
              ),
            ),
          BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) {
              // The IndexedStack keeps the search field alive: don't leave
              // its keyboard open over another tab.
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() => _selectedIndex = index);
            },
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
        ],
      ),
    );
  }
}
