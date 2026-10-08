import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/services/ads_config.dart';
// The default implementation pulls in google_mobile_ads, which has no web
// support, so web builds get a factory that never imports it.
import 'package:cadavre_exquisite/services/ads_service_factory.dart'
    if (dart.library.js_interop) 'package:cadavre_exquisite/services/ads_service_factory_web.dart';

export 'package:cadavre_exquisite/services/ads_config.dart' show AdPlacement;

/// Gathers ad consent, initializes the ads SDK and hands out ad unit ids.
///
/// Widgets use [instance]. Ads are disabled until [initialize] completes
/// successfully, so a banner must listen to [adsAvailable] (or check
/// [canShowAds]) and render nothing while it is `false`.
abstract class AdsService {
  static AdsService? _instance;

  /// The app-wide service: Google Mobile Ads on Android/iOS, a no-op
  /// everywhere else (web, desktop, `flutter test`). Tests may replace it.
  static AdsService get instance => _instance ??= createDefaultAdsService();
  static set instance(AdsService service) => _instance = service;

  /// Restores the platform default on next access to [instance].
  @visibleForTesting
  static void resetInstance() => _instance = null;

  /// Runs the consent flow (showing the consent form if required) and, if
  /// consent allows it, initializes the ads SDK. Safe to call more than once;
  /// later calls return the first call's future. Never throws: on any failure
  /// ads simply stay disabled.
  Future<void> initialize();

  /// `true` once ads may be requested. Starts `false` and flips to `true` at
  /// most once per session, after [initialize] (or [showPrivacyOptions])
  /// succeeds.
  ValueListenable<bool> get adsAvailable;

  /// Shorthand for `adsAvailable.value`.
  bool get canShowAds => adsAvailable.value;

  /// The banner ad unit id for [placement], or `null` when no banner must be
  /// shown there (ads not available yet, or not configured for this build).
  String? bannerUnitId(AdPlacement placement);

  /// The interstitial ad unit id, or `null` when interstitials must not be
  /// shown. Not used yet.
  String? interstitialUnitId();

  /// Whether the user must be offered a way to change their consent choices
  /// (the "Ad privacy settings" entry in the account screen). Starts `false`
  /// and is updated by [initialize] and [showPrivacyOptions].
  ValueListenable<bool> get privacyOptionsRequired;

  /// Shows the consent provider's privacy options form. No-op when not
  /// supported or not required.
  Future<void> showPrivacyOptions();
}

/// Never shows ads. Used on web, desktop and in tests.
class NoopAdsService extends AdsService {
  NoopAdsService();

  static final ValueNotifier<bool> _never = ValueNotifier(false);

  @override
  Future<void> initialize() async {}

  @override
  ValueListenable<bool> get adsAvailable => _never;

  @override
  String? bannerUnitId(AdPlacement placement) => null;

  @override
  String? interstitialUnitId() => null;

  @override
  ValueListenable<bool> get privacyOptionsRequired => _never;

  @override
  Future<void> showPrivacyOptions() async {}
}
