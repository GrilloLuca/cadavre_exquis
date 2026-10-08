import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Loads and shows a large anchored adaptive [BannerAd] for [adUnitId].
///
/// Use [AdBanner] instead of this widget directly: it decides whether a
/// banner may be shown at all.
///
/// The ad is sized to the width this widget is given (after horizontal safe
/// area insets) and is reloaded when that width or the orientation changes.
/// Nothing is rendered until the ad has loaded; a failed load renders nothing
/// and is not retried.
class AdBannerView extends StatefulWidget {
  const AdBannerView({super.key, required this.adUnitId});

  final String adUnitId;

  @override
  State<AdBannerView> createState() => _AdBannerViewState();
}

class _AdBannerViewState extends State<AdBannerView> {
  /// Space between the ad and adjacent controls, so taps meant for them
  /// don't land on the ad (AdMob placement policy).
  static const double _spacing = 8.0;

  /// The current ad, loading or loaded.
  BannerAd? _ad;
  bool _loaded = false;

  /// What [_ad] was (or is being) requested for.
  int? _width;
  Orientation? _orientation;

  /// Bumped on every new request and on dispose, so late callbacks from an
  /// outdated request are ignored.
  int _generation = 0;

  @override
  void dispose() {
    _generation++;
    _ad?.dispose();
    _ad = null;
    super.dispose();
  }

  /// Schedules a new ad if the available width or the orientation differs
  /// from what the current ad was requested for. Called during layout, so
  /// the actual work happens after the frame.
  void _requestFor(int width, Orientation orientation) {
    if (width <= 0) return;
    if (width == _width && orientation == _orientation) return;
    _width = width;
    _orientation = orientation;
    final generation = ++_generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation) {
        _load(width, orientation, generation);
      }
    });
  }

  Future<void> _load(int width, Orientation orientation, int generation) async {
    // An ad sized for the previous width/orientation no longer fits.
    final previous = _ad;
    if (previous != null) {
      setState(() {
        _ad = null;
        _loaded = false;
      });
      previous.dispose();
    }

    final AnchoredAdaptiveBannerAdSize? size;
    try {
      size = await AdSize.getLargeAnchoredAdaptiveBannerAdSizeWithOrientation(
        orientation,
        width,
      );
    } catch (_) {
      return;
    }
    if (size == null || !mounted || generation != _generation) return;

    final ad = BannerAd(
      adUnitId: widget.adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted || !identical(ad, _ad)) {
            ad.dispose();
            return;
          }
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (identical(ad, _ad)) _ad = null;
        },
      ),
    );
    _ad = ad;
    try {
      await ad.load();
    } catch (_) {
      ad.dispose();
      if (identical(ad, _ad)) _ad = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.orientationOf(context);
    // With adjustResize the banner would ride on top of the keyboard.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    // Keep horizontal insets (notch in landscape) out of the ad's width; the
    // bottom inset is only applied around a loaded ad, so a missing ad takes
    // no space at all.
    return SafeArea(
      top: false,
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          _requestFor(width.truncate(), orientation);

          final ad = _ad;
          if (ad == null || !_loaded || keyboardOpen) {
            return const SizedBox.shrink();
          }
          return ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              top: false,
              left: false,
              right: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Divider(height: 1.0, thickness: 1.0),
                  const SizedBox(height: _spacing),
                  SizedBox(
                    width: ad.size.width.toDouble(),
                    height: ad.size.height.toDouble(),
                    child: AdWidget(ad: ad),
                  ),
                  const SizedBox(height: _spacing),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
