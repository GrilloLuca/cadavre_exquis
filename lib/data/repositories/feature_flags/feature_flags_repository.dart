/// Switches the owner flips from the Firebase console, without a release.
abstract class FeatureFlagsRepository {
  /// Whether the email/password login button shows on the iOS welcome
  /// screen (for the App Store review's demo account). Emits `false` when
  /// the flag is missing or can't be read, then follows every change.
  Stream<bool> watchEmailLoginOnIos();
}
