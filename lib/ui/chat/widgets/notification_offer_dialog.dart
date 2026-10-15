import 'package:flutter/material.dart';

import 'package:cadavre_exquisite/l10n/app_localizations.dart';

/// Offers to turn on push notifications, before the system prompt (which
/// iOS shows only once). Pops with true to go on to the system prompt,
/// false or null for "Not now".
class NotificationOfferDialog extends StatelessWidget {
  const NotificationOfferDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      icon: const Icon(Icons.notifications_active_outlined),
      title: Text(l10n.notificationOfferTitle),
      content: Text(l10n.notificationOfferMessage),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.notificationOfferDecline),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.notificationOfferAccept),
        ),
      ],
    );
  }
}
