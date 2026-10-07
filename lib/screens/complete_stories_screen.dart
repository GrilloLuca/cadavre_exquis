import 'package:cadavre_exquisite/app_colors.dart';
import 'package:cadavre_exquisite/background.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/models/story.dart';
import 'package:cadavre_exquisite/services/story_service.dart';
import 'package:cadavre_exquisite/screens/story_read_screen.dart';

/// Non-story rows in the complete stories list.
enum _ListMarker { yourStoriesHeading, divider }

class CompleteStoriesScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final storyService = StoryService();
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Background(
        opacity: 0.2,
        child: StreamBuilder<List<Story>>(
          stream: storyService.completeStoriesStream(
            language: language,
            roomId: roomId,
          ),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final stories = snapshot.data!;
            if (stories.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Card(
                    color: AppColors.cream.withValues(alpha: 0.92),
                    elevation: 1.0,
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.0),
                    ),
                    child: Padding(
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
                ),
              );
            }

            // Stories the user took part in come first, then a divider,
            // then everyone else's.
            final email = FirebaseAuth.instance.currentUser?.email;
            final mine = <Story>[];
            final others = <Story>[];
            for (final story in stories) {
              (story.hasPartBy(email) ? mine : others).add(story);
            }

            // Markers stand in for the heading and the divider, so the list
            // can still be built lazily.
            final items = <Object>[
              if (mine.isNotEmpty) _ListMarker.yourStoriesHeading,
              ...mine,
              if (mine.isNotEmpty && others.isNotEmpty) _ListMarker.divider,
              ...others,
            ];

            return ListView.builder(
              padding: const EdgeInsets.all(12.0),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                switch (item) {
                  case _ListMarker.yourStoriesHeading:
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(8.0, 4.0, 8.0, 8.0),
                      child: Text(
                        l10n.yourStoriesHeading,
                        style: const TextStyle(
                          color: AppColors.primaryDark,
                          fontSize: 16.0,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  case _ListMarker.divider:
                    return const Divider(
                      height: 24.0,
                      thickness: 1.5,
                      indent: 8.0,
                      endIndent: 8.0,
                      color: AppColors.primaryDark,
                    );
                  case Story story:
                    return _buildStoryCard(context, story);
                  default:
                    throw StateError('Unexpected list item: $item');
                }
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildStoryCard(BuildContext context, Story story) {
    final l10n = AppLocalizations.of(context)!;
    final preview = story.parts.isNotEmpty ? story.parts.first.text : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Card(
        color: AppColors.cream.withValues(alpha: 0.92),
        elevation: 1.0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14.0),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 8.0,
          ),
          iconColor: AppColors.primary,
          textColor: AppColors.ink,
          leading: const Icon(Icons.menu_book),
          title: Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(l10n.authorsCount(story.parts.length)),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StoryReadScreen(story: story),
              ),
            );
          },
        ),
      ),
    );
  }
}
