import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/ads/ads_repository.dart';
import 'package:cadavre_exquisite/domain/models/ad_placement.dart';
// The mobile view pulls in google_mobile_ads, which has no web support, so
// web builds get a stub that never imports it.
import 'package:cadavre_exquisite/ui/core/ui/ad_banner_view.dart'
    if (dart.library.js_interop) 'package:cadavre_exquisite/ui/core/ui/ad_banner_view_web.dart';

/// An anchored banner ad for [placement], meant to sit at the bottom of a
/// screen, outside any scrolling content. Follows the [AdsRepository] above
/// it.
///
/// Renders nothing (zero size) until ads are available and the placement has
/// an ad unit id, while the ad is loading and if it fails to load. Space is
/// only taken once an ad has actually loaded.
class AdBanner extends StatelessWidget {
  const AdBanner({super.key, required this.placement});

  /// Which ad unit to show.
  final AdPlacement placement;

  @override
  Widget build(BuildContext context) {
    final ads = context.read<AdsRepository>();
    return ListenableBuilder(
      listenable: ads,
      builder: (context, _) {
        final adUnitId = ads.adsAvailable ? ads.bannerUnitId(placement) : null;
        if (adUnitId == null) return const SizedBox.shrink();
        // A new unit id means a new ad: start from a fresh state.
        return AdBannerView(key: ValueKey(adUnitId), adUnitId: adUnitId);
      },
    );
  }
}
