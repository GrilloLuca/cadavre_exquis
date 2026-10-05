import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/models/story.dart';

class StoryReadScreen extends StatelessWidget {
  final Story story;

  const StoryReadScreen({super.key, required this.story});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.storyCompleteTitle),
        backgroundColor: Colors.lightBlueAccent,
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(20.0),
          itemCount: story.parts.length,
          separatorBuilder: (_, __) => const Divider(height: 16.0, color: Colors.transparent,),
          itemBuilder: (context, index) {
            final part = story.parts[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Text(
                //   positionLabel(context, part.position),
                //   style: const TextStyle(
                //     fontWeight: FontWeight.bold,
                //     color: Colors.black54,
                //   ),
                // ),
                const SizedBox(height: 8.0),
                Text(part.text, style: const TextStyle(fontSize: 16.0, color: Colors.black54)),
                const SizedBox(height: 4.0),
                // Text(
                //   '— ${part.author}',
                //   style: const TextStyle(fontSize: 12.0, color: Colors.black38),
                // ),
              ],
            );
          },
        ),
      ),
    );
  }
}
