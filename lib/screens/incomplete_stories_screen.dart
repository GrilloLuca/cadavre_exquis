import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/models/story.dart';
import 'package:cadavre_exquisite/services/story_service.dart';
import 'package:cadavre_exquisite/screens/chat_screen.dart';
import 'package:cadavre_exquisite/typing_indicator.dart';

class IncompleteStoriesScreen extends StatefulWidget {
  const IncompleteStoriesScreen({super.key});

  @override
  State<IncompleteStoriesScreen> createState() =>
      _IncompleteStoriesScreenState();
}

class _IncompleteStoriesScreenState extends State<IncompleteStoriesScreen> {
  final _storyService = StoryService();

  @override
  Widget build(BuildContext context) {
    final currentUserEmail = FirebaseAuth.instance.currentUser?.email;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: StreamBuilder<List<Story>>(
        stream: _storyService.incompleteStoriesStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final stories = snapshot.data!
              .where((story) => !story.hasParticipated(currentUserEmail))
              .toList()
            ..sort((a, b) => a.parts.length.compareTo(b.parts.length));

          if (stories.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  l10n.noIncompleteStories,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12.0),
            itemCount: stories.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final story = stories[index];
              final isLocked = story.isLockedFor(currentUserEmail);
              return ListTile(
                leading:
                    isLocked ? const TypingIndicator() : const Icon(Icons.edit_note),
                title: Text(positionLabel(context, story.currentPosition)),
                subtitle: Text(
                  isLocked
                      ? l10n.storyBeingWritten
                      : story.parts.isEmpty
                          ? l10n.storyNotStarted
                          : '"...${story.lastFiveWords}"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                enabled: !isLocked,
                onTap: isLocked
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(story: story),
                          ),
                        );
                      },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _storyService.createStory(),
        tooltip: l10n.newStoryTooltip,
        child: const Icon(Icons.add),
      ),
    );
  }
}
