import 'package:flutter/material.dart';

import 'package:cadavre_exquisite/domain/models/story_notification.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/account/view_models/account_view_model.dart';
import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/ui/cream_card.dart';

/// The notifications section of the profile: whether push notifications are
/// on, and a button to turn them on when the user was never asked. A
/// refused permission can only be changed in the system settings. Rebuilt
/// by its parent when [viewModel] changes.
class NotificationsCard extends StatelessWidget {
  const NotificationsCard({super.key, required this.viewModel});

  final AccountViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final permission = viewModel.notificationPermission;
    final secondaryStyle = TextStyle(
      fontSize: 14.0,
      color: AppColors.ink.withValues(alpha: 0.75),
    );
    final (text, icon) = switch (permission) {
      NotificationPermission.granted => (
          l10n.notificationsOn,
          Icons.notifications_active_outlined,
        ),
      NotificationPermission.denied => (
          l10n.notificationsDenied,
          Icons.notifications_off_outlined,
        ),
      _ => (l10n.notificationsOff, Icons.notifications_none_outlined),
    };
    final enabling = viewModel.enableNotifications.running;

    return CreamCard(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: AppColors.primaryDark),
              const SizedBox(width: 8.0),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.notificationsSectionTitle,
                    style: const TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4.0),
          Text(text, style: secondaryStyle),
          if (permission == NotificationPermission.notDetermined) ...[
            const SizedBox(height: 12.0),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed:
                    enabling ? null : viewModel.enableNotifications.execute,
                child: Text(l10n.notificationsEnableButton),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
