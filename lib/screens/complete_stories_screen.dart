import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/models/story.dart';
import 'package:cadavre_exquisite/services/story_service.dart';
import 'package:cadavre_exquisite/screens/story_read_screen.dart';

class CompleteStoriesScreen extends StatelessWidget {
  const CompleteStoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storyService = StoryService();

    return Scaffold(
      body: StreamBuilder<List<Story>>(
        stream: storyService.completeStoriesStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final stories = snapshot.data!;
          if (stories.isEmpty) {
            return const Center(
              child: Text(
                'Nessuna storia completata, per ora.',
                style: TextStyle(color: Colors.black54),
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
                subtitle: Text('${story.parts.length} autori'),
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
