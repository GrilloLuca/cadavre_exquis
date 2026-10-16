import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/ui/ad_banner.dart';
import 'package:cadavre_exquisite/ui/core/ui/background.dart';
import 'package:cadavre_exquisite/ui/core/ui/cream_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/domain/models/ad_placement.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/story_read/view_models/story_read_view_model.dart';

/// Reads a completed [story]. Parts show right away with masked authors;
/// nicknames replace them once loaded. Creates its ViewModel once, in
/// `initState` (see `ChatScreen`), and disposes it.
class StoryReadScreen extends StatefulWidget {
  const StoryReadScreen({super.key, required this.story});

  final Story story;

  @override
  State<StoryReadScreen> createState() => _StoryReadScreenState();
}

class _StoryReadScreenState extends State<StoryReadScreen> {
  late final StoryReadViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = StoryReadViewModel(
      story: widget.story,
      profileRepository: context.read<UserProfileRepository>(),
    );
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

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
                              Text(
                                part.text,
                                style: const TextStyle(
                                  fontSize: 16.0,
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 4.0),
                              Text(
                                l10n.storyPartAuthor(
                                  _viewModel.authorNameOf(part) ??
                                      l10n.anonymousAuthor,
                                ),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12.0,
                                  color: AppColors.ink.withValues(alpha: 0.6),
                                ),
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
