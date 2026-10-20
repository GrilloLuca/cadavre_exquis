import 'package:cadavre_exquisite/data/repositories/ads/ads_repository.dart';
import 'package:cadavre_exquisite/domain/models/ad_placement.dart';

/// In-memory [AdsRepository] for ViewModel and widget tests. Never talks to
/// the ads SDK; ads are off by default, so screens look as without them.
/// The test sets [available], [privacyOptionsRequired] and [unitIds].
/// Records what was called in [calls] and the placements asked for in
/// [requested].
class FakeAdsRepository extends AdsRepository {
  FakeAdsRepository({
    bool available = false,
    bool privacyOptionsRequired = false,
    this.unitIds = const {},
  })  : _available = available,
        _privacyOptionsRequired = privacyOptionsRequired;

  bool _available;
  bool _privacyOptionsRequired;

  /// The ad unit id of each placement, handed out while [available].
  final Map<AdPlacement, String> unitIds;

  /// Every placement [bannerUnitId] was called for, in order.
  final List<AdPlacement> requested = [];

  /// `'initialize'`, `'showPrivacyOptions'`, in order.
  final List<String> calls = [];

  set available(bool value) {
    _available = value;
    notifyListeners();
  }

  set privacyOptionsRequired(bool value) {
    _privacyOptionsRequired = value;
    notifyListeners();
  }

  @override
  bool get adsAvailable => _available;

  @override
  bool get privacyOptionsRequired => _privacyOptionsRequired;

  @override
  String? bannerUnitId(AdPlacement placement) {
    requested.add(placement);
    return _available ? unitIds[placement] : null;
  }

  @override
  Future<void> initialize() async => calls.add('initialize');

  @override
  Future<void> showPrivacyOptions() async => calls.add('showPrivacyOptions');
}
