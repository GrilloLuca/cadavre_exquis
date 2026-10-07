import 'package:cadavre_exquisite/app_colors.dart';
import 'package:cadavre_exquisite/background.dart';
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
  bool _isCreating = false;

  /// Creates a new empty story and opens it right away, so the creator
  /// writes its introduction.
  Future<void> _createAndOpenStory() async {
    setState(() => _isCreating = true);
    try {
      final story = await _storyService.createStory(
        language: widget.language,
        roomId: widget.roomId,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(story: story)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.genericError),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserEmail = FirebaseAuth.instance.currentUser?.email;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Background(
        opacity: 0.2,
        child: StreamBuilder<List<Story>>(
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
                        l10n.noIncompleteStories,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.ink),
                      ),
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
                final isLocked = story.isLockedFor(currentUserEmail);
                final isWaitingForOthers =
                    story.wasLastWrittenBy(currentUserEmail);
                final isDisabled = isLocked || isWaitingForOthers;
                return Card(
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
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isCreating ? null : _createAndOpenStory,
        tooltip: l10n.newStoryTooltip,
        child: const Icon(Icons.add),
      ),
    );
  }
}
