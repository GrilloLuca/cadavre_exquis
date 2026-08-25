import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/models/story.dart';
import 'package:cadavre_exquisite/services/story_service.dart';
import 'package:cadavre_exquisite/screens/story_read_screen.dart';

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
      body: StreamBuilder<List<Story>>(
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
              child: Text(
                l10n.noCompleteStories,
                style: const TextStyle(color: Colors.black54),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12.0),
            itemCount: stories.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final story = stories[index];
              final preview =
                  story.parts.isNotEmpty ? story.parts.first.text : '';
              return ListTile(
                leading: const Icon(Icons.menu_book),
                title: Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
              );
            },
          );
        },
      ),
    );
  }
}
