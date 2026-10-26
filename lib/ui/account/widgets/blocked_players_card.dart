import 'package:flutter/material.dart';

import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/account/view_models/account_view_model.dart';
import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/ui/cream_card.dart';

/// The players the user blocked, each with an Unblock button. Rebuilt by
/// its parent when [viewModel] changes.
class BlockedPlayersCard extends StatelessWidget {
  const BlockedPlayersCard({super.key, required this.viewModel});

  final AccountViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final keys = viewModel.blockedKeys;
    final unblocking = viewModel.unblock.running;

    return CreamCard(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.block, color: AppColors.primaryDark),
              const SizedBox(width: 8.0),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.blockedAuthorsTitle,
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
          if (keys.isEmpty)
            Text(
              l10n.blockedAuthorsEmpty,
              style: TextStyle(
                fontSize: 14.0,
                color: AppColors.ink.withValues(alpha: 0.75),
              ),
            )
          else
            for (final key in keys)
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      viewModel.blockedNameOf(key),
                      style: const TextStyle(
                        fontSize: 16.0,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: unblocking
                        ? null
                        : () => viewModel.unblock.execute(key),
                    child: Text(l10n.unblockButton),
                  ),
                ],
              ),
        ],
      ),
    );
  }
}
