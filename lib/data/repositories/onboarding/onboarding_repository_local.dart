import 'package:cadavre_exquisite/data/repositories/onboarding/onboarding_repository.dart';
import 'package:cadavre_exquisite/data/services/onboarding_preference.dart';

/// [OnboardingRepository] kept on the device. Starts loading on creation.
class OnboardingRepositoryLocal extends OnboardingRepository {
  OnboardingRepositoryLocal({required OnboardingPreference preference})
      : _preference = preference {
    _load();
  }

  final OnboardingPreference _preference;
  bool _isReady = false;
  bool _hasSeen = false;
  bool _disposed = false;

  @override
  bool get isReady => _isReady;

  @override
  bool get hasSeen => _hasSeen;

  Future<void> _load() async {
    try {
      // markSeen may have run while this was reading.
      _hasSeen = _hasSeen || await _preference.hasSeen();
    } catch (_) {
      // Unreadable storage: showing the slides again is harmless.
    }
    _isReady = true;
    if (!_disposed) notifyListeners();
  }

  @override
  Future<void> markSeen() async {
    // Leave the slides at once; the write can finish in the background.
    _hasSeen = true;
    if (!_disposed) notifyListeners();
    await _preference.markSeen();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
