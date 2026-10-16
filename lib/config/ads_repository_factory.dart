import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/ads/ads_repository.dart';
import 'package:cadavre_exquisite/data/repositories/ads/ads_repository_admob.dart';
import 'package:cadavre_exquisite/data/repositories/ads/ads_repository_noop.dart';

/// Google Mobile Ads on Android and iOS; no ads on desktop, where the SDK is
/// absent.
AdsRepository createAdsRepository() => switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => AdsRepositoryAdmob(),
      _ => AdsRepositoryNoop(),
    };
