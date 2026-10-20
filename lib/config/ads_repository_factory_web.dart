import 'package:cadavre_exquisite/data/repositories/ads/ads_repository.dart';
import 'package:cadavre_exquisite/data/repositories/ads/ads_repository_noop.dart';

/// Web: google_mobile_ads is not supported, so ads are always off.
AdsRepository createAdsRepository() => AdsRepositoryNoop();
