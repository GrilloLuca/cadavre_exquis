import 'package:flutter/material.dart';

// The mobile view pulls in google_mobile_ads, which has no web support, so
// web builds get a stub that never imports it.
import 'package:cadavre_exquisite/ad_banner_view.dart'
    if (dart.library.js_interop) 'package:cadavre_exquisite/ad_banner_view_web.dart';
import 'package:cadavre_exquisite/services/ads_service.dart';

/// An anchored banner ad for [placement], meant to sit at the bottom of a
/// screen, outside any scrolling content.
///
/// Renders nothing (zero size) until ads are available and the placement has
/// an ad unit id, while the ad is loading, if it fails to load, and while the
/// keyboard is open. Space is only reserved once an ad has actually loaded.
class AdBanner extends StatelessWidget {
  const AdBanner({super.key, required this.placement, this.adsService});

  /// Which ad unit to show.
  final AdPlacement placement;

  /// Source of ad availability and unit ids; defaults to
  /// [AdsService.instance]. Injectable for tests.
  final AdsService? adsService;

  @override
  Widget build(BuildContext context) {
    final service = adsService ?? AdsService.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: service.adsAvailable,
      builder: (context, available, _) {
        final adUnitId = available ? service.bannerUnitId(placement) : null;
        if (adUnitId == null) return const SizedBox.shrink();
        // A new unit id means a new ad: start from a fresh state.
        return AdBannerView(key: ValueKey(adUnitId), adUnitId: adUnitId);
      },
    );
  }
}
