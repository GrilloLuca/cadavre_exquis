import 'package:flutter/widgets.dart';

/// Web: google_mobile_ads is not supported, so banners never render.
class AdBannerView extends StatelessWidget {
  const AdBannerView({super.key, required this.adUnitId});

  final String adUnitId;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
