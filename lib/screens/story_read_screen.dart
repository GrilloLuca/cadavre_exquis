import 'package:cadavre_exquisite/app_colors.dart';
import 'package:cadavre_exquisite/background.dart';
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
        backgroundColor: AppColors.primary,
      ),
      body: Background(
        opacity: 0.2,
        child: SafeArea(
          // One cream card holds the whole story; it hugs short stories and
          // scrolls with long ones.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12.0),
            child: Card(
              color: AppColors.cream.withValues(alpha: 0.92),
              elevation: 1.0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, part) in story.parts.indexed) ...[
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
                      // Text(
                      //   '— ${part.author}',
                      //   style: const TextStyle(fontSize: 12.0, color: Colors.black38),
                      // ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
