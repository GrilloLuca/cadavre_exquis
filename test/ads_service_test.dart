import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/services/ads_config.dart';
import 'package:cadavre_exquisite/services/ads_service.dart';
import 'package:cadavre_exquisite/services/google_ads_service.dart';

const _android = TargetPlatform.android;
const _ios = TargetPlatform.iOS;

const _releaseConfig = AdsConfig(
  useTestIds: false,
  releaseBanners: {
    AdPlacement.completeStoriesBanner: PlatformAdUnit(
      android: 'ca-app-pub-1111111111111111/1000000001',
      ios: 'ca-app-pub-1111111111111111/1000000002',
    ),
    AdPlacement.storyReadBanner: PlatformAdUnit(
      android: 'ca-app-pub-1111111111111111/1000000003',
      ios: 'ca-app-pub-1111111111111111/1000000004',
    ),
  },
  releaseInterstitial: PlatformAdUnit(
    android: 'ca-app-pub-1111111111111111/1000000005',
    ios: 'ca-app-pub-1111111111111111/1000000006',
  ),
);

void main() {
  group('AdsConfig with test ids (non-release)', () {
    // Release ids are ignored when test ids are in use.
    const config = AdsConfig(
      useTestIds: true,
      releaseBanners: {
        AdPlacement.completeStoriesBanner:
            PlatformAdUnit(android: 'ca-app-pub-1111111111111111/1'),
      },
    );

    test('every banner placement uses Google test banner ids', () {
      for (final placement in AdPlacement.values) {
        expect(config.bannerUnitId(placement, _android),
            'ca-app-pub-3940256099942544/9214589741');
        expect(config.bannerUnitId(placement, _ios),
            'ca-app-pub-3940256099942544/2435281174');
      }
    });

    test('interstitial uses Google test interstitial ids', () {
      expect(config.interstitialUnitId(_android),
          'ca-app-pub-3940256099942544/1033173712');
      expect(config.interstitialUnitId(_ios),
          'ca-app-pub-3940256099942544/4411468910');
    });

    test('no ids on unsupported platforms', () {
      expect(
          config.bannerUnitId(
              AdPlacement.storyReadBanner, TargetPlatform.macOS),
          isNull);
      expect(config.interstitialUnitId(TargetPlatform.linux), isNull);
      expect(config.hasAnyAdUnit(TargetPlatform.windows), isFalse);
    });
  });

  group('AdsConfig with release ids', () {
    test('returns the configured id per placement and platform', () {
      expect(
          _releaseConfig.bannerUnitId(
              AdPlacement.completeStoriesBanner, _android),
          'ca-app-pub-1111111111111111/1000000001');
      expect(
          _releaseConfig.bannerUnitId(AdPlacement.completeStoriesBanner, _ios),
          'ca-app-pub-1111111111111111/1000000002');
      expect(_releaseConfig.bannerUnitId(AdPlacement.storyReadBanner, _android),
          'ca-app-pub-1111111111111111/1000000003');
      expect(_releaseConfig.bannerUnitId(AdPlacement.storyReadBanner, _ios),
          'ca-app-pub-1111111111111111/1000000004');
      expect(_releaseConfig.interstitialUnitId(_android),
          'ca-app-pub-1111111111111111/1000000005');
      expect(_releaseConfig.interstitialUnitId(_ios),
          'ca-app-pub-1111111111111111/1000000006');
      expect(_releaseConfig.hasAnyAdUnit(_android), isTrue);
    });

    test('trims surrounding whitespace', () {
      const config = AdsConfig(
        useTestIds: false,
        releaseInterstitial:
            PlatformAdUnit(android: '  ca-app-pub-1111111111111111/42 '),
      );
      expect(config.interstitialUnitId(_android),
          'ca-app-pub-1111111111111111/42');
    });
  });

  group('AdsConfig fail-closed in release', () {
    test('nothing configured disables every ad, never test ids', () {
      const config = AdsConfig(useTestIds: false);
      for (final platform in [_android, _ios]) {
        for (final placement in AdPlacement.values) {
          expect(config.bannerUnitId(placement, platform), isNull);
        }
        expect(config.interstitialUnitId(platform), isNull);
        expect(config.hasAnyAdUnit(platform), isFalse);
      }
    });

    test('a missing id only disables that placement/platform', () {
      const config = AdsConfig(
        useTestIds: false,
        releaseBanners: {
          AdPlacement.storyReadBanner:
              PlatformAdUnit(android: 'ca-app-pub-1111111111111111/7'),
        },
      );
      expect(config.bannerUnitId(AdPlacement.storyReadBanner, _android),
          'ca-app-pub-1111111111111111/7');
      expect(config.bannerUnitId(AdPlacement.storyReadBanner, _ios), isNull);
      expect(config.bannerUnitId(AdPlacement.completeStoriesBanner, _android),
          isNull);
      expect(config.hasAnyAdUnit(_android), isTrue);
      expect(config.hasAnyAdUnit(_ios), isFalse);
    });

    test('rejects Google test ids, App IDs and malformed values', () {
      for (final bad in [
        'ca-app-pub-3940256099942544/9214589741', // test banner
        'ca-app-pub-1111111111111111~1234567890', // App ID, not ad unit
        'not-an-id',
        '   ',
      ]) {
        final config = AdsConfig(
          useTestIds: false,
          releaseInterstitial: PlatformAdUnit(android: bad),
        );
        expect(config.interstitialUnitId(_android), isNull, reason: bad);
      }
    });
  });

  group('AdsService.instance', () {
    tearDown(AdsService.resetInstance);

    test('defaults to the no-op service under flutter test', () {
      final service = AdsService.instance;
      expect(service, isA<NoopAdsService>());
    });

    test('can be overridden', () {
      final fake = NoopAdsService();
      AdsService.instance = fake;
      expect(AdsService.instance, same(fake));
    });
  });

  group('NoopAdsService', () {
    test('never shows ads', () async {
      final service = NoopAdsService();
      await service.initialize();
      await service.showPrivacyOptions();
      expect(service.canShowAds, isFalse);
      expect(service.adsAvailable.value, isFalse);
      expect(service.privacyOptionsRequired.value, isFalse);
      expect(service.interstitialUnitId(), isNull);
      for (final placement in AdPlacement.values) {
        expect(service.bannerUnitId(placement), isNull);
      }
    });
  });

  group('GoogleAdsService before initialization', () {
    test('hands out no ad unit ids until ads are available', () {
      final service = GoogleAdsService(config: _releaseConfig, platform: _ios);
      expect(service.canShowAds, isFalse);
      expect(service.bannerUnitId(AdPlacement.storyReadBanner), isNull);
      expect(service.interstitialUnitId(), isNull);
    });

    test('initialize is a no-op when no ad unit is configured', () async {
      // Must complete without touching the (absent) native SDK.
      final service = GoogleAdsService(
          config: const AdsConfig(useTestIds: false), platform: _android);
      await service.initialize();
      expect(service.canShowAds, isFalse);
    });
  });
}
