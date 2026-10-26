import 'package:flutter/material.dart';

import 'package:cadavre_exquisite/domain/models/content_report.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/core/view_models/part_safety_actions.dart';

/// A small menu next to another player's [part]: report it (after picking
/// a reason) or block its author (after confirming). Runs [actions]'
/// commands; the screen listens to them for the feedback.
class PartSafetyMenu extends StatelessWidget {
  const PartSafetyMenu({
    super.key,
    required this.actions,
    required this.part,
    required this.authorName,
    this.color,
  });

  final PartSafetyActions actions;
  final StoryPart part;

  /// The author as shown on screen, for the block confirmation.
  final String authorName;

  final Color? color;

  Future<void> _report(BuildContext context) async {
    final reason = await showDialog<ReportReason>(
      context: context,
      builder: (_) => const _ReportReasonDialog(),
    );
    if (reason == null) return;
    actions.report.execute((part: part, reason: reason));
  }

  Future<void> _block(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l10n.blockAuthorTitle(authorName)),
          content: Text(l10n.blockAuthorMessage(authorName)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancelButton),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.blockAuthorConfirmButton),
            ),
          ],
        );
      },
    );
    if (confirmed == true) actions.block.execute(part);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<_Action>(
      tooltip: l10n.partSafetyMenuTooltip,
      icon: Icon(Icons.more_vert, color: color),
      onSelected: (action) => switch (action) {
        _Action.report => _report(context),
        _Action.block => _block(context),
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _Action.report,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.flag_outlined),
            title: Text(l10n.reportPartMenuItem),
          ),
        ),
        PopupMenuItem(
          value: _Action.block,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.block),
            title: Text(l10n.blockAuthorMenuItem(authorName)),
          ),
        ),
      ],
    );
  }
}

enum _Action { report, block }

class _ReportReasonDialog extends StatelessWidget {
  const _ReportReasonDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    String label(ReportReason reason) => switch (reason) {
          ReportReason.offensive => l10n.reportReasonOffensive,
          ReportReason.sexual => l10n.reportReasonSexual,
          ReportReason.harassment => l10n.reportReasonHarassment,
          ReportReason.spam => l10n.reportReasonSpam,
          ReportReason.other => l10n.reportReasonOther,
        };
    return SimpleDialog(
      title: Text(l10n.reportReasonTitle),
      children: [
        for (final reason in ReportReason.values)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, reason),
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
            child: Text(label(reason)),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancelButton),
            ),
          ),
        ),
      ],
    );
  }
}

/// Listens to [actions] for [State] and shows the outcome: a thank-you
/// after a report, and after a block [onBlocked] (the screens close, since
/// the story is now hidden) followed by a snack bar naming [authorName].
/// Errors show the generic message.
class PartSafetyFeedback {
  PartSafetyFeedback({
    required this.actions,
    required this.context,
    required this.authorName,
    required this.onBlocked,
  }) {
    actions.report.addListener(_onReport);
    actions.block.addListener(_onBlock);
  }

  final PartSafetyActions actions;
  final BuildContext context;
  final String Function(StoryPart part) authorName;
  final VoidCallback onBlocked;

  void _show(ScaffoldMessengerState messenger, String text) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _onReport() {
    final report = actions.report;
    // clearResult notifies again, with nothing left to show.
    if (report.running || !context.mounted) return;
    if (report.error == null && !report.completed) return;
    final l10n = AppLocalizations.of(context)!;
    _show(
      ScaffoldMessenger.of(context),
      report.error != null ? l10n.genericError : l10n.reportSentSnackbar,
    );
    report.clearResult();
  }

  void _onBlock() {
    final block = actions.block;
    if (block.running || !context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    // The messenger outlives the screen [onBlocked] may close.
    final messenger = ScaffoldMessenger.of(context);
    if (block.error != null) {
      block.clearResult();
      _show(messenger, l10n.genericError);
      return;
    }
    final part = block.value;
    if (!block.completed || part == null) return;
    block.clearResult();
    _show(messenger, l10n.authorBlockedSnackbar(authorName(part)));
    onBlocked();
  }

  void dispose() {
    actions.report.removeListener(_onReport);
    actions.block.removeListener(_onBlock);
  }
}
