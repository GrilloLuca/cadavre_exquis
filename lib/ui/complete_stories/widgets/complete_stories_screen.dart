import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/complete_stories/view_models/complete_stories_view_model.dart';
import 'package:cadavre_exquisite/ui/complete_stories/widgets/age_check_screen.dart';
import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/ui/background.dart';
import 'package:cadavre_exquisite/ui/core/ui/cream_card.dart';
import 'package:cadavre_exquisite/ui/story_read/widgets/story_read_screen.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// Most of the screen's height the "Your stories" panel may take when
/// other stories are listed below it.
const _yourStoriesMaxHeightFactor = 0.4;

/// The completed stories of the room, newest first. Stories the AI review
/// flagged as mature are listed with the others but locked behind the age
/// check ([AgeGate]); known minors don't see them at all. Creates its
/// [CompleteStoriesViewModel] once, in `initState` (see `ChatScreen`).
class CompleteStoriesScreen extends StatefulWidget {
  /// Language code of the room the user has joined: only stories in this
  /// language are listed.
  final String language;

  /// Id of the private room the user has joined, if any. When set, this
  /// takes precedence over [language]: only stories in this room are listed.
  final String? roomId;

  const CompleteStoriesScreen({
    super.key,
    required this.language,
    this.roomId,
  });

  @override
  State<CompleteStoriesScreen> createState() => _CompleteStoriesScreenState();
}

class _CompleteStoriesScreenState extends State<CompleteStoriesScreen> {
  late final CompleteStoriesViewModel _viewModel;

  // One controller per list: two lists on the PrimaryScrollController
  // break its scrollbar on iOS and desktop, where it's interactive.
  final _yourStoriesScroll = ScrollController();
  final _otherStoriesScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _viewModel = CompleteStoriesViewModel(
      storyRepository: context.read<StoryRepository>(),
      authRepository: context.read<AuthRepository>(),
      ageGate: context.read<AgeGate>(),
      language: widget.language,
      roomId: widget.roomId,
    );
    _viewModel.unlock.addListener(_onUnlockChanged);
    _viewModel.submitBirthYear.addListener(_onSubmitBirthYearChanged);
  }

  @override
  void didUpdateWidget(CompleteStoriesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The user switched room or language.
    _viewModel.setRoom(language: widget.language, roomId: widget.roomId);
  }

  @override
  void dispose() {
    _viewModel.unlock.removeListener(_onUnlockChanged);
    _viewModel.submitBirthYear.removeListener(_onSubmitBirthYearChanged);
    _viewModel.dispose();
    _yourStoriesScroll.dispose();
    _otherStoriesScroll.dispose();
    super.dispose();
  }

  void _openStory(Story story) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryReadScreen(story: story),
      ),
    );
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Acts on the outcome of an unlock step: opens the story for adults,
  /// tells minors it's unavailable, or shows the birth-year screen.
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
        _openStory(result.story);
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

    return Scaffold(
      body: Background(
        opacity: 0.2,
        child: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            if (!_viewModel.isLoaded) {
              return const Center(child: CircularProgressIndicator());
            }

            // Stories the user took part in come first, then a divider,
            // then everyone else's. Both groups keep the repository's
            // order (newest completed first).
            final (:mine, :others) = _viewModel.sections;
            if (mine.isEmpty && others.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: CreamCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20.0,
                      vertical: 16.0,
                    ),
                    child: Text(
                      l10n.noCompleteStories,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.ink),
                    ),
                  ),
                ),
              );
            }

            // The user's stories sit in a panel pinned at the top, which
            // scrolls on its own; everyone else's fill the rest of the
            // screen with their own scroll.
            if (mine.isEmpty) {
              return _buildStoryList(others, _otherStoriesScroll);
            }
            if (others.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildYourStoriesHeading(l10n),
                  Expanded(
                    child:
                        _buildStoryList(mine, _yourStoriesScroll, top: false),
                  ),
                ],
              );
            }
            return LayoutBuilder(
              builder: (context, constraints) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildYourStoriesHeading(l10n),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight:
                          constraints.maxHeight * _yourStoriesMaxHeightFactor,
                    ),
                    child: _buildStoryList(mine, _yourStoriesScroll,
                        top: false, shrinkWrap: true),
                  ),
                  const Divider(
                    height: 24.0,
                    thickness: 1.5,
                    indent: 20.0,
                    endIndent: 20.0,
                    color: AppColors.primaryDark,
                  ),
                  Expanded(
                    child: _buildStoryList(others, _otherStoriesScroll,
                        top: false),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildYourStoriesHeading(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 8.0),
      child: Text(
        l10n.yourStoriesHeading,
        style: const TextStyle(
          color: AppColors.primaryDark,
          fontSize: 16.0,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// A scrollable list of story cards, with a scrollbar so a list that
  /// scrolls on its own shows it. Without [top] padding when a heading
  /// sits right above it. [shrinkWrap] lets a short list take only the
  /// height it needs.
  Widget _buildStoryList(
    List<Story> stories,
    ScrollController controller, {
    bool top = true,
    bool shrinkWrap = false,
  }) {
    return Scrollbar(
      controller: controller,
      child: ListView.builder(
        controller: controller,
        shrinkWrap: shrinkWrap,
        padding: EdgeInsets.fromLTRB(12.0, top ? 12.0 : 0.0, 12.0, 12.0),
        itemCount: stories.length,
        itemBuilder: (context, index) =>
            _buildStoryCard(context, stories[index]),
      ),
    );
  }

  Widget _buildStoryCard(BuildContext context, Story story) {
    final l10n = AppLocalizations.of(context)!;
    final locked = _viewModel.isLocked(story);
    final unlockedMature = story.mature == true && !locked;

    final Widget tile;
    if (locked) {
      // The AI title is generated child-safe, so it is shown; the part text
      // never is, as it can contain what the review flagged. A story the
      // model refused to read has no title and falls back to the label.
      final title = story.title;
      tile = Semantics(
        button: true,
        onTapHint: l10n.matureStoryUnlockHint,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 8.0,
          ),
          iconColor: AppColors.primary,
          textColor: AppColors.ink,
          leading: Icon(
            Icons.lock,
            size: 24.0,
            color: AppColors.primaryDark,
            semanticLabel: l10n.matureStoryLockedLabel,
          ),
          title: Text(
            title ?? l10n.matureStoryLockedTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            title == null
                ? l10n.authorsCount(story.parts.length)
                : '${l10n.matureStoryLockedTitle} · '
                    '${l10n.authorsCount(story.parts.length)}',
          ),
          trailing: _viewModel.checkingStoryId == story.id
              ? const SizedBox(
                  width: 18.0,
                  height: 18.0,
                  child: CircularProgressIndicator(strokeWidth: 2.0),
                )
              : null,
          onTap: () => _viewModel.unlock.execute(story),
        ),
      );
    } else {
      final preview = story.parts.isNotEmpty ? story.parts.first.text : '';
      tile = ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 8.0,
        ),
        iconColor: AppColors.primary,
        textColor: AppColors.ink,
        leading: const Icon(Icons.menu_book),
        title: Text(
          story.title ?? preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(l10n.authorsCount(story.parts.length)),
        trailing: unlockedMature
            ? Icon(
                Icons.lock_open,
                size: 20.0,
                semanticLabel: l10n.matureStoryAdultContent,
              )
            : null,
        onTap: () => _openStory(story),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: CreamCard(child: tile),
    );
  }
}
