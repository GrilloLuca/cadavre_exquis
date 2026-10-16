import 'package:flutter/material.dart';

import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/ui/cream_card.dart';

/// The top of the writing screen: which part the player is writing
/// ("Parte 2 di 4"), what to do, and what the story is about so far.
///
/// The copy depends only on [position] (one of [kStoryPositions]); an
/// unknown position hides the progress and reads as a middle part.
class ChatTurnCard extends StatelessWidget {
  const ChatTurnCard({
    super.key,
    required this.position,
    this.keywords = const [],
  });

  final String position;

  /// The story's keywords; the section is hidden when empty. Pass none for
  /// a story without parts.
  final List<String> keywords;

  static const _headingStyle = TextStyle(
    color: AppColors.primaryDark,
    fontSize: 13.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final index = kStoryPositions.indexOf(position);
    final isFirst = index == 0;
    final isLast = index == kStoryPositions.length - 1;

    return CreamCard(
      padding: const EdgeInsets.all(16.0),
      // A Card merges its content into one node; keep the headings (and
      // their header flag) apart so screen readers can jump between them.
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (index != -1) ...[
              _Progress(current: index + 1, total: kStoryPositions.length),
              const SizedBox(height: 12.0),
            ],
            Semantics(
              header: true,
              child: Text(
                isFirst
                    ? l10n.chatHeadlineFirst
                    : isLast
                        ? l10n.chatHeadlineLast
                        : l10n.chatHeadlineMiddle,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 20.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6.0),
            Text(
              isFirst
                  ? l10n.chatLeadFirst
                  : isLast
                      ? l10n.chatLeadLast
                      : l10n.chatLeadMiddle,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 15.0,
                height: 1.4,
              ),
            ),
            if (keywords.isNotEmpty) ...[
              const SizedBox(height: 20.0),
              _Keywords(keywords: keywords),
            ],
          ],
        ),
      ),
    );
  }
}

/// Four segments (done, current, still to write) and "Parte n di 4". The
/// segments are decoration: the text carries the meaning.
class _Progress extends StatelessWidget {
  const _Progress({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final future = BoxDecoration(
      borderRadius: BorderRadius.circular(3.0),
      border: Border.all(
        color: AppColors.ink.withValues(alpha: 0.3),
        width: 1.5,
      ),
    );
    return Row(
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160.0),
            child: ExcludeSemantics(
              child: Row(
                key: const ValueKey('chatProgressSegments'),
                children: [
                  for (var i = 1; i <= total; i++) ...[
                    if (i > 1) const SizedBox(width: 6.0),
                    Expanded(
                      child: SizedBox(
                        height: 6.0,
                        child: DecoratedBox(
                          decoration: i > current
                              ? future
                              : BoxDecoration(
                                  color: i == current
                                      ? AppColors.primaryDark
                                      : AppColors.primary,
                                  borderRadius: BorderRadius.circular(3.0),
                                ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12.0),
        Flexible(
          child: Text(
            l10n.chatPartProgress(current, total),
            style: TextStyle(
              color: AppColors.ink.withValues(alpha: 0.75),
              fontSize: 13.0,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// "Di cosa parla finora": up to 4 keywords as plain sage labels (not
/// buttons). The keywords are story content, so
/// they're never translated.
class _Keywords extends StatelessWidget {
  const _Keywords({required this.keywords});

  final List<String> keywords;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.storyKeywordsLabel,
              style: ChatTurnCard._headingStyle,
            ),
          ),
          const SizedBox(height: 8.0),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: [
              for (final keyword in keywords.take(4))
                DecoratedBox(
                  decoration: const ShapeDecoration(
                    color: AppColors.sage,
                    shape: StadiumBorder(),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 6.0,
                    ),
                    child: Text(
                      keyword,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 14.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
