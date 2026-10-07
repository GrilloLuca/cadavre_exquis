import 'package:cadavre_exquisite/app_colors.dart';
import 'package:cadavre_exquisite/background.dart';
import 'package:cadavre_exquisite/cream_card.dart';
import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/models/author_name.dart';
import 'package:cadavre_exquisite/models/story.dart';
import 'package:cadavre_exquisite/services/user_profile_service.dart';

class StoryReadScreen extends StatefulWidget {
  final Story story;

  /// Source of the authors' nicknames; injectable for tests.
  final UserProfileService? profileService;

  const StoryReadScreen({super.key, required this.story, this.profileService});

  @override
  State<StoryReadScreen> createState() => _StoryReadScreenState();
}

class _StoryReadScreenState extends State<StoryReadScreen> {
  /// Authors' nicknames, fetched once. Never fails: a failed lookup simply
  /// leaves that author without a nickname.
  late final Future<Map<String, String>> _nicknames;

  @override
  void initState() {
    super.initState();
    final service = widget.profileService ?? UserProfileService();
    _nicknames = service
        .nicknamesFor(widget.story.parts.map((p) => p.author))
        .catchError((Object _) => const <String, String>{});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final story = widget.story;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.storyCompleteTitle),
        backgroundColor: AppColors.primary,
      ),
      body: Background(
        opacity: 0.2,
        child: SafeArea(
          // One cream card holds the whole story; it hugs short stories and
          // scrolls with long ones.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12.0),
            child: CreamCard(
              padding: const EdgeInsets.all(20.0),
              // Parts render immediately with the masked-email fallback;
              // nicknames replace it once they arrive.
              child: FutureBuilder<Map<String, String>>(
                future: _nicknames,
                initialData: const <String, String>{},
                builder: (context, snapshot) {
                  final nicknames = snapshot.data ?? const <String, String>{};
                  return Column(
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
                        const SizedBox(height: 4.0),
                        Text(
                          l10n.storyPartAuthor(
                            authorDisplayName(
                                  nickname: nicknames[part.author],
                                  email: part.author,
                                ) ??
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
      ),
    );
  }
}
