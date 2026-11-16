import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/onboarding/onboarding_repository.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// Closing the first-launch onboarding slides, by finishing or skipping
/// them.
class OnboardingViewModel extends ChangeNotifier {
  OnboardingViewModel({required OnboardingRepository onboardingRepository})
      : _onboarding = onboardingRepository {
    complete = Command0<void>(_onboarding.markSeen);
  }

  final OnboardingRepository _onboarding;

  /// Records the onboarding as seen; `AuthWrapper` then moves on.
  late final Command0<void> complete;

  @override
  void dispose() {
    complete.dispose();
    super.dispose();
  }
}
