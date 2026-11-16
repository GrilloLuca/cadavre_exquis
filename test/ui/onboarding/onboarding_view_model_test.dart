import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/ui/onboarding/view_models/onboarding_view_model.dart';

import '../../../testing/fakes/repositories/fake_onboarding_repository.dart';

void main() {
  test('complete marks the onboarding seen', () async {
    final onboarding = FakeOnboardingRepository(hasSeen: false);
    final viewModel = OnboardingViewModel(onboardingRepository: onboarding);

    await viewModel.complete.execute();

    expect(onboarding.hasSeen, isTrue);
    expect(onboarding.markSeenCalls, 1);
    expect(viewModel.complete.completed, isTrue);
    viewModel.dispose();
  });
}
