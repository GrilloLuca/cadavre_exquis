import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/ui/background.dart';
import 'package:cadavre_exquisite/ui/core/ui/cream_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/ui/core/position_label.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/ui/chat/view_models/chat_view_model.dart';
import 'package:cadavre_exquisite/ui/chat/widgets/chat_screen.dart';
import 'package:cadavre_exquisite/ui/core/ui/typing_indicator.dart';
import 'package:cadavre_exquisite/ui/incomplete_stories/view_models/incomplete_stories_view_model.dart';

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
      language: widget.language,
      roomId: widget.roomId,
    );
    _viewModel.createStory.addListener(_onCreateStoryChanged);
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

  /// Opens the chat screen to write the next part of [story].
  void _openChat(Story story) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          viewModel: ChatViewModel(
            story: story,
            storyRepository: context.read<StoryRepository>(),
            authRepository: context.read<AuthRepository>(),
          ),
        ),
      ),
    );
  }

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
          onPressed: _viewModel.createStory.running
              ? null
              : _viewModel.createStory.execute,
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
      itemBuilder: (context, index) {
        final story = stories[index];
        final status = _viewModel.statusOf(story);
        final isLocked = status == IncompleteStoryStatus.beingWritten;
        final isWaitingForOthers =
            status == IncompleteStoryStatus.waitingForOthers;
        final isDisabled = status != IncompleteStoryStatus.available;
        return CreamCard(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            iconColor: AppColors.primary,
            textColor: AppColors.ink,
            leading: isLocked
                ? const TypingIndicator()
                : Icon(isWaitingForOthers
                    ? Icons.hourglass_empty
                    : Icons.edit_note),
            title: Text(
              positionLabel(context, story.currentPosition),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              isLocked
                  ? l10n.storyBeingWritten
                  : isWaitingForOthers
                      ? l10n.storyWaitingForOthers
                      : story.parts.isEmpty
                          ? l10n.storyNotStarted
                          : '"...${story.lastFiveWords}"',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            enabled: !isDisabled,
            onTap: isDisabled ? null : () => _openChat(story),
          ),
        );
      },
    );
  }
}
