import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/ui/ad_banner.dart';
import 'package:cadavre_exquisite/ui/core/ui/background.dart';
import 'package:cadavre_exquisite/ui/core/ui/cream_card.dart';
import 'package:cadavre_exquisite/ui/core/ui/part_safety_menu.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/safety/safety_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/domain/models/ad_placement.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/story_read/view_models/story_read_view_model.dart';

/// Reads a completed [story]. Parts show right away with masked authors;
/// nicknames replace them once loaded. Each part by another player has a
/// menu to report it or block its author; blocking closes the screen, as
/// the story is then hidden. Creates its ViewModel once, in `initState`
/// (see `ChatScreen`), and disposes it.
class StoryReadScreen extends StatefulWidget {
  const StoryReadScreen({super.key, required this.story});

  final Story story;

  @override
  State<StoryReadScreen> createState() => _StoryReadScreenState();
}

class _StoryReadScreenState extends State<StoryReadScreen> {
  late final StoryReadViewModel _viewModel;
  late final PartSafetyFeedback _safetyFeedback;

  @override
  void initState() {
    super.initState();
    _viewModel = StoryReadViewModel(
      story: widget.story,
      profileRepository: context.read<UserProfileRepository>(),
      safetyRepository: context.read<SafetyRepository>(),
      authRepository: context.read<AuthRepository>(),
    );
    _safetyFeedback = PartSafetyFeedback(
      actions: _viewModel.safety,
      context: context,
      authorName: _authorName,
      onBlocked: () => Navigator.pop(context),
    );
  }

  @override
  void dispose() {
    _safetyFeedback.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  String _authorName(StoryPart part) =>
      _viewModel.authorNameOf(part) ??
      AppLocalizations.of(context)!.anonymousAuthor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final story = _viewModel.story;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.storyCompleteTitle),
        backgroundColor: AppColors.primary,
      ),
      body: Background(
        opacity: 0.2,
        child: SafeArea(
          child: Column(
            children: [
              // One cream card holds the whole story; it hugs short
              // stories and scrolls with long ones.
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12.0),
                  child: CreamCard(
                    padding: const EdgeInsets.all(20.0),
                    // Parts render immediately with the masked-email fallback;
                    // nicknames replace it once they arrive.
                    child: ListenableBuilder(
                      listenable: _viewModel.loadNicknames,
                      builder: (context, _) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (story.title != null) ...[
                              Text(
                                story.title!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 22.0,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                              const SizedBox(height: 20.0),
                            ],
                            for (final (index, part)
                                in story.parts.indexed) ...[
                              if (index > 0) const SizedBox(height: 16.0),
                              // Text(
                              //   positionLabel(context, part.position),
                              //   style: const TextStyle(
                              //     fontWeight: FontWeight.bold,
                              //     color: Colors.black54,
                              //   ),
                              // ),
                              if (part.removed)
                                Text(
                                  l10n.partRemovedByModeration,
                                  style: TextStyle(
                                    fontSize: 16.0,
                                    fontStyle: FontStyle.italic,
                                    color: AppColors.ink.withValues(alpha: 0.6),
                                  ),
                                )
                              else
                                Text(
                                  part.text,
                                  style: const TextStyle(
                                    fontSize: 16.0,
                                    color: AppColors.ink,
                                  ),
                                ),
                              const SizedBox(height: 4.0),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      l10n.storyPartAuthor(_authorName(part)),
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 12.0,
                                        color: AppColors.ink
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ),
                                  if (!part.removed &&
                                      _viewModel.safety.canActOn(part))
                                    PartSafetyMenu(
                                      actions: _viewModel.safety,
                                      part: part,
                                      authorName: _authorName(part),
                                      color:
                                          AppColors.ink.withValues(alpha: 0.6),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              // Anchored below the story, outside the scroll view.
              const AdBanner(placement: AdPlacement.storyReadBanner),
            ],
          ),
        ),
      ),
    );
  }
}
