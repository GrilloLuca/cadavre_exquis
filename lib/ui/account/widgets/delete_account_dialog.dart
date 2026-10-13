import 'package:flutter/material.dart';

import 'package:cadavre_exquisite/l10n/app_localizations.dart';

/// The user's answer to [DeleteAccountDialog]: [password] is set for
/// email/password users and null for Google users.
class DeleteConfirmation {
  const DeleteConfirmation(this.password);

  final String? password;
}

/// Confirms deleting the account; for email/password users it also asks
/// for the password. Pops with a [DeleteConfirmation], or null if cancelled.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key, required this.usesPassword});

  final bool usesPassword;

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _confirm() {
    if (widget.usesPassword && _passwordController.text.isEmpty) return;
    Navigator.pop(
      context,
      DeleteConfirmation(
        widget.usesPassword ? _passwordController.text : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.deleteAccountTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l10n.deleteAccountMessage),
          const SizedBox(height: 16.0),
          if (widget.usesPassword)
            TextField(
              controller: _passwordController,
              obscureText: true,
              autofocus: true,
              onSubmitted: (_) => _confirm(),
              decoration: InputDecoration(hintText: l10n.passwordHint),
            )
          else
            Text(l10n.deleteAccountGoogleHint),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelButton),
        ),
        TextButton(
          onPressed: _confirm,
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text(l10n.deleteAccountConfirmButton),
        ),
      ],
    );
  }
}
