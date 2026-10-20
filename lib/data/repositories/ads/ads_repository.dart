import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/domain/models/ad_placement.dart';

/// Banner ads: gathering the user's ad consent, starting the ads SDK and
/// handing out ad unit ids.
///
/// Ads stay off until [initialize] succeeds, so a banner follows
/// [adsAvailable] (it notifies when it changes) and renders nothing while
/// it is false.
abstract class AdsRepository extends ChangeNotifier {
  /// Whether ads may be requested. Starts false and turns true at most once
  /// per session, after [initialize] (or [showPrivacyOptions]) succeeds.
  bool get adsAvailable;

  /// Whether the user must be offered a way to change their ad consent (the
  /// "Ad privacy settings" entry in the profile tab; EEA/UK only). Starts
  /// false and is updated by [initialize] and [showPrivacyOptions].
  bool get privacyOptionsRequired;

  /// The banner ad unit id for [placement], or null when no banner must be
  /// shown there (ads not available yet, or not configured for this build).
  String? bannerUnitId(AdPlacement placement);

  /// Runs the consent flow (showing the consent form if required) and, if
  /// consent allows it, starts the ads SDK. Later calls return the first
  /// call's future. Never throws: on any failure ads simply stay off.
  Future<void> initialize();

  /// Shows the consent provider's privacy options form. Never throws; does
  /// nothing where it isn't supported or required.
  Future<void> showPrivacyOptions();
}
