import 'package:cadavre_exquisite/data/repositories/ads/ads_repository.dart';
import 'package:cadavre_exquisite/domain/models/ad_placement.dart';

/// Never shows ads. Used on web and desktop, where the ads SDK is absent.
class AdsRepositoryNoop extends AdsRepository {
  @override
  bool get adsAvailable => false;

  @override
  bool get privacyOptionsRequired => false;

  @override
  String? bannerUnitId(AdPlacement placement) => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> showPrivacyOptions() async {}
}
