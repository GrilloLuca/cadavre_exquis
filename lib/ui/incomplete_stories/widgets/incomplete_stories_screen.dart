import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/ui/background.dart';
import 'package:cadavre_exquisite/ui/core/ui/cream_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/domain/models/app_config.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/ui/core/position_label.dart';
import 'package:cadavre_exquisite/data/repositories/safety/safety_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/ui/chat/widgets/chat_screen.dart';
import 'package:cadavre_exquisite/ui/complete_stories/widgets/age_check_screen.dart';
import 'package:cadavre_exquisite/ui/core/ui/typing_indicator.dart';
import 'package:cadavre_exquisite/ui/core/view_models/mature_story_access.dart';
import 'package:cadavre_exquisite/ui/incomplete_stories/view_models/incomplete_stories_view_model.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// The incomplete stories of the room, each with what the user can do with
/// it: write the next part, wait (someone else is writing, the user wrote
/// the last part, or its latest part is being reviewed), or go through the
/// age check for a mature story (see docs/PART_MODERATION_UI_SPEC.md §2).
/// Creates its [IncompleteStoriesViewModel] once, in `initState`.
class IncompleteStoriesScreen extends StatefulWidget {
  /// Language code of the room the user has joined: only stories in this
  /// language are listed, and new stories are created in it.
  final String language;

  /// Id of the private room the user has joined, if any. When set, this
  /// takes precedence over [language]: only stories in this room are listed
  /// and created.
  final String? roomId;

  const IncompleteStoriesScreen({
    super.key,
    required this.language,
    this.roomId,
  });

  @override
  State<IncompleteStoriesScreen> createState() =>
      _IncompleteStoriesScreenState();
}

class _IncompleteStoriesScreenState extends State<IncompleteStoriesScreen> {
  late final IncompleteStoriesViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = IncompleteStoriesViewModel(
      storyRepository: context.read<StoryRepository>(),
      authRepository: context.read<AuthRepository>(),
      safetyRepository: context.read<SafetyRepository>(),
      ageGate: context.read<AgeGate>(),
      language: widget.language,
      roomId: widget.roomId,
      matureVisibleToMinors: context.read<AppConfig>().matureVisibleToMinors,
    );
    _viewModel.createStory.addListener(_onCreateStoryChanged);
    _viewModel.unlock.addListener(_onUnlockChanged);
    _viewModel.submitBirthYear.addListener(_onSubmitBirthYearChanged);
  }

  @override
  void didUpdateWidget(IncompleteStoriesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The user switched room or language.
    _viewModel.setRoom(language: widget.language, roomId: widget.roomId);
  }

  @override
  void dispose() {
    _viewModel.createStory.removeListener(_onCreateStoryChanged);
    _viewModel.unlock.removeListener(_onUnlockChanged);
    _viewModel.submitBirthYear.removeListener(_onSubmitBirthYearChanged);
    _viewModel.dispose();
    super.dispose();
  }

  /// Opens a newly created story right away, so the creator writes its
  /// introduction.
  void _onCreateStoryChanged() {
    final command = _viewModel.createStory;
    if (command.running) return;
    if (command.error != null) {
      command.clearResult();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.genericError),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final story = command.value;
    if (command.completed && story != null) {
      command.clearResult();
      _openChat(story);
    }
  }

  /// Starts a story, or explains why the user has to wait first.
  void _onNewStoryPressed() {
    if (!_viewModel.canCreateStory) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.newStoryBlocked),
        ),
      );
      return;
    }
    _viewModel.createStory.execute();
  }

  /// Opens the chat screen to write the next part of [story].
  void _openChat(Story story) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(story: story)),
    );
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Acts on the outcome of an unlock step, as the completed stories list
  /// does: opens the chat for adults (if the story changed meanwhile, the
  /// chat's lock fails and says why), tells minors it's unavailable, or
  /// shows the birth-year screen.
  Future<void> _handle(Command<UnlockResult> command) async {
    if (command.running) return;
    final l10n = AppLocalizations.of(context)!;
    if (command.error != null) {
      command.clearResult();
      _showSnackBar(l10n.genericError);
      return;
    }
    final result = command.value;
    if (!command.completed || result == null) return;
    command.clearResult();
    switch (result.outcome) {
      case UnlockOutcome.open:
        _openChat(result.story);
      case UnlockOutcome.minor:
        _showSnackBar(l10n.matureStoryUnavailable);
      case UnlockOutcome.askBirthYear:
        final birthYear = await Navigator.push<int>(
          context,
          MaterialPageRoute(builder: (_) => const AgeCheckScreen()),
        );
        if (!mounted) return;
        if (birthYear == null) {
          _viewModel.cancelBirthYear();
        } else {
          _viewModel.submitBirthYear.execute(birthYear);
        }
      case UnlockOutcome.ignored:
        break;
    }
  }

  void _onUnlockChanged() => _handle(_viewModel.unlock);

  void _onSubmitBirthYearChanged() => _handle(_viewModel.submitBirthYear);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return ListenableBuilder(
      listenable: Listenable.merge([_viewModel, _viewModel.createStory]),
      builder: (context, _) => Scaffold(
        body: Background(
          opacity: 0.2,
          child: _buildList(context, l10n),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed:
              _viewModel.createStory.running || _viewModel.stories == null
                  ? null
                  : _onNewStoryPressed,
          tooltip: l10n.newStoryTooltip,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, AppLocalizations l10n) {
    final stories = _viewModel.stories;
    if (stories == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (stories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: CreamCard(
            padding: const EdgeInsets.symmetric(
              horizontal: 20.0,
              vertical: 16.0,
            ),
            child: Text(
              l10n.noIncompleteStories,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.ink),
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12.0),
      itemCount: stories.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8.0),
      itemBuilder: (context, index) =>
          _buildStoryCard(context, l10n, stories[index]),
    );
  }

  /// One story's tile, in the state [IncompleteStoriesViewModel.statusOf]
  /// gives it. Every state has the same height, and the card is keyed by
  /// story, so a tile that changes state live keeps screen-reader focus.
  /// The last five words show only on tiles the user can open without the
  /// age check (available, or unlocked for a session adult).
  Widget _buildStoryCard(
    BuildContext context,
    AppLocalizations l10n,
    Story story,
  ) {
    final status = _viewModel.statusOf(story);
    final mature = _viewModel.matureStateOf(story);
    // A disabled tile of a mature story the user can't open shows the
    // padlock, without an explicit colour so it takes the disabled tint.
    final padlocked = mature == MatureTileState.locked ||
        mature == MatureTileState.unavailable;
    final disabledPadlock = Icon(
      Icons.lock,
      size: 24.0,
      semanticLabel: l10n.matureStoryLockedLabel,
    );

    final Widget leading;
    final String subtitle;
    Widget? trailing;
    VoidCallback? onTap;
    switch (status) {
      case IncompleteStoryStatus.available:
        leading = const Icon(Icons.edit_note);
        subtitle = story.parts.isEmpty
            ? l10n.storyNotStarted
            : story.lastPartRemoved
                ? l10n.partRemovedByModeration
                : '"...${story.lastFiveWords}"';
        if (mature == MatureTileState.unlocked) {
          trailing = Icon(
            Icons.lock_open,
            size: 20.0,
            semanticLabel: l10n.matureStoryAdultContent,
          );
        }
        onTap = () => _openChat(story);
      case IncompleteStoryStatus.underReview:
        // Decorative: the subtitle says why.
        leading = const Icon(Icons.hourglass_top);
        subtitle = l10n.storyUnderReview;
      case IncompleteStoryStatus.beingWritten:
        leading = padlocked ? disabledPadlock : const TypingIndicator();
        subtitle = l10n.storyBeingWritten;
      case IncompleteStoryStatus.waitingForOthers:
        leading =
            padlocked ? disabledPadlock : const Icon(Icons.hourglass_empty);
        subtitle = l10n.storyWaitingForOthers;
      case IncompleteStoryStatus.locked:
        leading = Icon(
          Icons.lock,
          size: 24.0,
          color: AppColors.primaryDark,
          semanticLabel: l10n.matureStoryLockedLabel,
        );
        subtitle = l10n.matureStoryLockedTitle;
        if (_viewModel.checkingStoryId == story.id) {
          trailing = const SizedBox(
            width: 18.0,
            height: 18.0,
            child: CircularProgressIndicator(strokeWidth: 2.0),
          );
        }
        onTap = () => _viewModel.unlock.execute(story);
      case IncompleteStoryStatus.unavailable:
        leading = disabledPadlock;
        subtitle = l10n.matureStoryUnavailableLabel;
    }

    Widget tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 8.0,
      ),
      iconColor: AppColors.primary,
      textColor: AppColors.ink,
      leading: leading,
      title: Text(
        positionLabel(context, story.currentPosition),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
      enabled: onTap != null,
      onTap: onTap,
    );
    if (status == IncompleteStoryStatus.locked) {
      tile = Semantics(
        button: true,
        onTapHint: l10n.matureStoryUnlockHint,
        child: tile,
      );
    }
    return CreamCard(key: ValueKey(story.id), child: tile);
  }
}
