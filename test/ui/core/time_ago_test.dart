import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/core/time_ago.dart';

void main() {
  late AppLocalizations l10n;
  final now = DateTime.utc(2026, 10, 12, 10);

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  String ago(Duration elapsed) =>
      timeAgo(l10n, now.subtract(elapsed), now: now);

  test('under a minute is just now', () {
    expect(ago(const Duration(seconds: 59)), 'just now');
  });

  test('a time in the future is just now', () {
    expect(ago(const Duration(minutes: -5)), 'just now');
  });

  test('counts minutes under an hour', () {
    expect(ago(const Duration(minutes: 1)), '1 minute ago');
    expect(ago(const Duration(minutes: 59)), '59 minutes ago');
  });

  test('counts hours under a day', () {
    expect(ago(const Duration(hours: 1)), '1 hour ago');
    expect(ago(const Duration(hours: 23, minutes: 59)), '23 hours ago');
  });

  test('counts days from then on', () {
    expect(ago(const Duration(days: 1)), '1 day ago');
    expect(ago(const Duration(days: 40)), '40 days ago');
  });

  test('is translated', () async {
    final it = await AppLocalizations.delegate.load(const Locale('it'));
    expect(timeAgo(it, now.subtract(const Duration(hours: 4)), now: now),
        '4 ore fa');
  });
}
