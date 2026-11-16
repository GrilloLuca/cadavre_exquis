import 'package:cadavre_exquisite/data/repositories/onboarding/onboarding_repository.dart';

/// In-memory [OnboardingRepository] for ViewModel and widget tests, already
/// loaded. Counts [markSeen] calls in [markSeenCalls].
class FakeOnboardingRepository extends OnboardingRepository {
  FakeOnboardingRepository({bool hasSeen = true}) : _hasSeen = hasSeen;

  bool _hasSeen;
  int markSeenCalls = 0;

  @override
  bool get isReady => true;

  @override
  bool get hasSeen => _hasSeen;

  @override
  Future<void> markSeen() async {
    markSeenCalls++;
    _hasSeen = true;
    notifyListeners();
  }
}
