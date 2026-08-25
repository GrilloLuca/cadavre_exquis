import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/models/story.dart';
import 'package:cadavre_exquisite/services/story_service.dart';
import 'package:cadavre_exquisite/screens/chat_screen.dart';
import 'package:cadavre_exquisite/typing_indicator.dart';

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
  final _storyService = StoryService();

  @override
  Widget build(BuildContext context) {
    final currentUserEmail = FirebaseAuth.instance.currentUser?.email;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: StreamBuilder<List<Story>>(
        stream: _storyService.incompleteStoriesStream(
          language: widget.language,
          roomId: widget.roomId,
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final stories = snapshot.data!.toList()
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
              final isWaitingForOthers =
                  story.wasLastWrittenBy(currentUserEmail);
              final isDisabled = isLocked || isWaitingForOthers;
              return ListTile(
                leading: isLocked
                    ? const TypingIndicator()
                    : Icon(isWaitingForOthers
                        ? Icons.hourglass_empty
                        : Icons.edit_note),
                title: Text(positionLabel(context, story.currentPosition)),
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
                onTap: isDisabled
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
        onPressed: () => _storyService.createStory(
          language: widget.language,
          roomId: widget.roomId,
        ),
        tooltip: l10n.newStoryTooltip,
        child: const Icon(Icons.add),
      ),
    );
  }
}
