import 'package:flutter/foundation.dart';

/// Where an ad is shown in the app. Each placement has its own ad unit so
/// they can be tracked separately in the AdMob console.
enum AdPlacement { completeStoriesBanner, storyReadBanner }

/// A pair of ad unit ids, one per mobile platform. An empty string means
/// "not configured".
class PlatformAdUnit {
  const PlatformAdUnit({this.android = '', this.ios = ''});

  final String android;
  final String ios;

  String _raw(TargetPlatform platform) => switch (platform) {
        TargetPlatform.android => android,
        TargetPlatform.iOS => ios,
        _ => '',
      };
}

/// Chooses the AdMob ad unit ids for the current build.
///
/// - Non-release builds (`!kReleaseMode`) always use Google's official TEST
///   ad unit ids, whatever was passed via `--dart-define`.
/// - Release builds only use the ids passed at build time via
///   `--dart-define` (see the `ADMOB_*` names below). A missing, malformed or
///   test id disables that ad (fail-closed): release builds never fall back
///   to test ids.
///
/// Release `--dart-define` names:
/// - `ADMOB_BANNER_COMPLETE_STORIES_ANDROID`, `ADMOB_BANNER_COMPLETE_STORIES_IOS`
/// - `ADMOB_BANNER_STORY_READ_ANDROID`, `ADMOB_BANNER_STORY_READ_IOS`
/// - `ADMOB_INTERSTITIAL_ANDROID`, `ADMOB_INTERSTITIAL_IOS`
class AdsConfig {
  const AdsConfig({
    required this.useTestIds,
    this.releaseBanners = const {},
    this.releaseInterstitial = const PlatformAdUnit(),
  });

  /// Whether to use Google's test ad units instead of [releaseBanners] and
  /// [releaseInterstitial].
  final bool useTestIds;
  final Map<AdPlacement, PlatformAdUnit> releaseBanners;
  final PlatformAdUnit releaseInterstitial;

  /// Google's publisher id for its sample/test ad units.
  static const String testPublisherId = '3940256099942544';

  static const PlatformAdUnit testBanner = PlatformAdUnit(
    android: 'ca-app-pub-3940256099942544/9214589741',
    ios: 'ca-app-pub-3940256099942544/2435281174',
  );
  static const PlatformAdUnit testInterstitial = PlatformAdUnit(
    android: 'ca-app-pub-3940256099942544/1033173712',
    ios: 'ca-app-pub-3940256099942544/4411468910',
  );

  /// The configuration for this build.
  static const AdsConfig current = AdsConfig(
    useTestIds: !kReleaseMode,
    releaseBanners: {
      AdPlacement.completeStoriesBanner: PlatformAdUnit(
        android:
            String.fromEnvironment('ADMOB_BANNER_COMPLETE_STORIES_ANDROID'),
        ios: String.fromEnvironment('ADMOB_BANNER_COMPLETE_STORIES_IOS'),
      ),
      AdPlacement.storyReadBanner: PlatformAdUnit(
        android: String.fromEnvironment('ADMOB_BANNER_STORY_READ_ANDROID'),
        ios: String.fromEnvironment('ADMOB_BANNER_STORY_READ_IOS'),
      ),
    },
    releaseInterstitial: PlatformAdUnit(
      android: String.fromEnvironment('ADMOB_INTERSTITIAL_ANDROID'),
      ios: String.fromEnvironment('ADMOB_INTERSTITIAL_IOS'),
    ),
  );

  /// The banner ad unit id for [placement] on [platform], or `null` when ads
  /// must not be shown there.
  String? bannerUnitId(AdPlacement placement, TargetPlatform platform) {
    if (useTestIds) return _nonEmpty(testBanner._raw(platform));
    return _validReleaseId(releaseBanners[placement]?._raw(platform));
  }

  /// The interstitial ad unit id on [platform], or `null` when interstitials
  /// must not be shown.
  String? interstitialUnitId(TargetPlatform platform) {
    if (useTestIds) return _nonEmpty(testInterstitial._raw(platform));
    return _validReleaseId(releaseInterstitial._raw(platform));
  }

  /// Whether at least one ad unit is configured on [platform]. When false
  /// there is no point in initializing the SDK or asking for consent.
  bool hasAnyAdUnit(TargetPlatform platform) =>
      AdPlacement.values.any((p) => bannerUnitId(p, platform) != null) ||
      interstitialUnitId(platform) != null;

  /// `ca-app-pub-<publisher>/<unit>`; rejects App IDs (`~`) passed by mistake.
  static final RegExp _adUnitIdPattern = RegExp(r'^ca-app-pub-\d+/\d+$');

  static String? _nonEmpty(String value) => value.isEmpty ? null : value;

  static String? _validReleaseId(String? raw) {
    final id = raw?.trim() ?? '';
    if (!_adUnitIdPattern.hasMatch(id)) return null;
    if (id.contains(testPublisherId)) return null;
    return id;
  }
}
