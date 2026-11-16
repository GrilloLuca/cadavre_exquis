import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cadavre_exquisite/data/repositories/onboarding/onboarding_repository_local.dart';
import 'package:cadavre_exquisite/data/services/onboarding_preference.dart';

void main() {
  Future<OnboardingRepositoryLocal> loaded() async {
    final repository = OnboardingRepositoryLocal(
      preference:
          OnboardingPreference(prefs: await SharedPreferences.getInstance()),
    );
    while (!repository.isReady) {
      await Future<void>.delayed(Duration.zero);
    }
    return repository;
  }

  test('is not seen on a fresh install', () async {
    SharedPreferences.setMockInitialValues({});

    expect((await loaded()).hasSeen, isFalse);
  });

  test('stays seen after markSeen, across restarts', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await loaded();
    var notified = false;
    first.addListener(() => notified = true);

    await first.markSeen();

    expect(first.hasSeen, isTrue);
    expect(notified, isTrue);
    expect((await loaded()).hasSeen, isTrue);
  });
}
