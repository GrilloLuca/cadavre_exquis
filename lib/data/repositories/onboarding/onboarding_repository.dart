import 'package:flutter/foundation.dart';

/// Whether the first-launch onboarding has been seen. Notifies listeners
/// when it is loaded and when it is marked seen.
abstract class OnboardingRepository extends ChangeNotifier {
  /// False until the stored answer has been read.
  bool get isReady;

  /// Whether the user has finished or skipped the onboarding.
  bool get hasSeen;

  /// Records that the onboarding was finished or skipped.
  Future<void> markSeen();
}
