import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/services/ads_service.dart';

/// An [AdsService] whose availability and unit ids the test controls. Never
/// talks to the ads SDK.
class FakeAdsService extends AdsService {
  FakeAdsService({
    bool available = false,
    bool privacyOptionsRequired = false,
    this.unitIds = const {},
  })  : _available = ValueNotifier(available),
        _privacyOptionsRequired = ValueNotifier(privacyOptionsRequired);

  final ValueNotifier<bool> _available;
  final ValueNotifier<bool> _privacyOptionsRequired;
  final Map<AdPlacement, String> unitIds;
  final List<AdPlacement> requested = [];

  int privacyOptionsShown = 0;

  set available(bool value) => _available.value = value;
  set privacyOptionsRequiredValue(bool value) =>
      _privacyOptionsRequired.value = value;

  @override
  ValueListenable<bool> get adsAvailable => _available;

  @override
  String? bannerUnitId(AdPlacement placement) {
    requested.add(placement);
    return canShowAds ? unitIds[placement] : null;
  }

  @override
  Future<void> initialize() async {}

  @override
  String? interstitialUnitId() => null;

  @override
  ValueListenable<bool> get privacyOptionsRequired => _privacyOptionsRequired;

  @override
  Future<void> showPrivacyOptions() async => privacyOptionsShown++;
}
