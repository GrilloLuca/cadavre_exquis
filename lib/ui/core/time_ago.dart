import 'package:cadavre_exquisite/l10n/app_localizations.dart';

/// How long ago [time] was, e.g. "4 hours ago": just now under a minute,
/// then minutes, hours and days. A [time] in the future (clock skew) counts
/// as just now. [now] defaults to the current time; tests pass a fixed one.
String timeAgo(AppLocalizations l10n, DateTime time, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(time);
  if (elapsed.inMinutes < 1) return l10n.timeJustNow;
  if (elapsed.inHours < 1) return l10n.timeMinutesAgo(elapsed.inMinutes);
  if (elapsed.inDays < 1) return l10n.timeHoursAgo(elapsed.inHours);
  return l10n.timeDaysAgo(elapsed.inDays);
}
