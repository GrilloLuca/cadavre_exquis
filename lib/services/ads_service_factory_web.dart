import 'package:cadavre_exquisite/services/ads_service.dart';

/// Web: google_mobile_ads is not supported, so ads are always off.
AdsService createDefaultAdsService() => NoopAdsService();
