import 'package:flutter/widgets.dart';

import 'package:cadavre_exquisite/l10n/app_localizations.dart';

/// The localized name of a story [position] (one of `kStoryPositions`), or
/// the raw value for an unknown one.
String positionLabel(BuildContext context, String position) {
  final l10n = AppLocalizations.of(context)!;
  switch (position) {
    case 'introduzione':
      return l10n.positionIntroduction;
    case 'sviluppo1':
      return l10n.positionDevelopment1;
    case 'sviluppo2':
      return l10n.positionDevelopment2;
    case 'epilogo':
      return l10n.positionEpilogue;
    default:
      return position;
  }
}
