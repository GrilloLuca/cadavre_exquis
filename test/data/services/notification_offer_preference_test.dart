import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cadavre_exquisite/data/services/notification_offer_preference.dart';

void main() {
  final now = DateTime.utc(2026, 10, 13);

  group('NotificationOfferPolicy', () {
    test('offers until the first "Not now"', () {
      expect(
        NotificationOfferPolicy.shouldOffer(
            dismissals: 0, lastDismissedAt: null, now: now),
        isTrue,
      );
    });

    test('offers again a week after the first "Not now"', () {
      bool offer(Duration ago) => NotificationOfferPolicy.shouldOffer(
          dismissals: 1, lastDismissedAt: now.subtract(ago), now: now);
      expect(offer(const Duration(days: 6)), isFalse);
      expect(offer(const Duration(days: 7)), isTrue);
    });

    test('stops after the second "Not now"', () {
      expect(
        NotificationOfferPolicy.shouldOffer(
          dismissals: 2,
          lastDismissedAt: now.subtract(const Duration(days: 365)),
          now: now,
        ),
        isFalse,
      );
    });
  });

  test('NotificationOfferPreference counts the dismissals', () async {
    SharedPreferences.setMockInitialValues({});
    final preference = NotificationOfferPreference(
        prefs: await SharedPreferences.getInstance());

    expect(await preference.shouldOffer(now), isTrue);
    await preference.recordDismissal(now);
    expect(await preference.shouldOffer(now), isFalse);
    expect(
        await preference.shouldOffer(now.add(const Duration(days: 8))), isTrue);
    await preference.recordDismissal(now.add(const Duration(days: 8)));
    expect(await preference.shouldOffer(now.add(const Duration(days: 100))),
        isFalse);
  });

  test('remembers that the permission was requested', () async {
    SharedPreferences.setMockInitialValues({});
    final preference = NotificationOfferPreference(
        prefs: await SharedPreferences.getInstance());

    expect(await preference.wasPermissionRequested(), isFalse);
    await preference.recordPermissionRequested();
    expect(await preference.wasPermissionRequested(), isTrue);
  });
}
