import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/services/ads_service.dart';
import 'package:cadavre_exquisite/services/google_ads_service.dart';

/// Non-web: Google Mobile Ads on Android/iOS; a no-op on desktop and under
/// `flutter test` (which sets `FLUTTER_TEST`), where the native SDK is absent.
AdsService createDefaultAdsService() {
  if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
    return NoopAdsService();
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => GoogleAdsService(),
    _ => NoopAdsService(),
  };
}
