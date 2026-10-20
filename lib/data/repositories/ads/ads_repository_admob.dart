import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:cadavre_exquisite/data/repositories/ads/ads_config.dart';
import 'package:cadavre_exquisite/data/repositories/ads/ads_repository.dart';
import 'package:cadavre_exquisite/domain/models/ad_placement.dart';

/// Debug-only: make the UMP consent flow behave as if the device were in the
/// EEA, to test the consent form. Enable with
/// `--dart-define=ADMOB_DEBUG_EEA=true`; ignored in release builds. Emulators
/// are test devices automatically; physical devices must be listed (hashed
/// ids, comma separated, printed by the UMP SDK in the device log) in
/// `--dart-define=ADMOB_TEST_DEVICE_IDS=...`.
const bool _debugForceEeaConsent = bool.fromEnvironment('ADMOB_DEBUG_EEA');
const String _debugTestDeviceIds =
    String.fromEnvironment('ADMOB_TEST_DEVICE_IDS');

/// [AdsRepository] backed by Google Mobile Ads and the User Messaging
/// Platform (UMP) consent SDK. Only created on Android and iOS.
class AdsRepositoryAdmob extends AdsRepository {
  AdsRepositoryAdmob({
    AdsConfig config = AdsConfig.current,
    TargetPlatform? platform,
  })  : _config = config,
        _platform = platform ?? defaultTargetPlatform;

  final AdsConfig _config;
  final TargetPlatform _platform;
  Future<void>? _initialization;
  Future<void>? _sdkInitialization;

  bool _adsAvailable = false;
  bool _privacyOptionsRequired = false;
  bool _disposed = false;

  @override
  bool get adsAvailable => _adsAvailable;

  @override
  bool get privacyOptionsRequired => _privacyOptionsRequired;

  @override
  String? bannerUnitId(AdPlacement placement) =>
      _adsAvailable ? _config.bannerUnitId(placement, _platform) : null;

  @override
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    // Fail-closed: with no ad unit for this build there is nothing to show,
    // so don't ask for consent or start the SDK.
    if (!_config.hasAnyAdUnit(_platform)) {
      debugPrint('AdsRepository: no ad units configured, ads disabled');
      return;
    }
    try {
      final updated = await _requestConsentInfoUpdate();
      if (updated) await _loadAndShowConsentFormIfRequired();
      // Even if the update failed, consent gathered in a previous session
      // may still allow requesting ads.
      await _refreshPrivacyOptionsRequired();
      await _startSdkIfAllowed();
    } catch (e) {
      debugPrint('AdsRepository: initialization failed, ads disabled: $e');
    }
  }

  @override
  Future<void> showPrivacyOptions() async {
    try {
      final completer = Completer<void>();
      await ConsentForm.showPrivacyOptionsForm((error) {
        if (error != null) {
          debugPrint('AdsRepository: privacy options form error: '
              '${error.errorCode} ${error.message}');
        }
        if (!completer.isCompleted) completer.complete();
      });
      await completer.future;
      await _refreshPrivacyOptionsRequired();
      // The user may have just granted consent they had denied before.
      await _startSdkIfAllowed();
    } catch (e) {
      debugPrint('AdsRepository: privacy options failed: $e');
    }
  }

  /// Completes with whether the consent info update succeeded.
  Future<bool> _requestConsentInfoUpdate() {
    final completer = Completer<bool>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      _consentRequestParameters(),
      () => completer.complete(true),
      (error) {
        debugPrint('AdsRepository: consent info update failed: '
            '${error.errorCode} ${error.message}');
        completer.complete(false);
      },
    );
    return completer.future;
  }

  Future<void> _loadAndShowConsentFormIfRequired() async {
    final completer = Completer<void>();
    await ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (error != null) {
        debugPrint('AdsRepository: consent form error: '
            '${error.errorCode} ${error.message}');
      }
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
  }

  ConsentRequestParameters _consentRequestParameters() {
    // TODO(admob): the target-audience/age decision is still open. Once made,
    // set `tagForUnderAgeOfConsent` here accordingly; left unspecified for now.
    if (kReleaseMode || !_debugForceEeaConsent) {
      return ConsentRequestParameters();
    }
    return ConsentRequestParameters(
      consentDebugSettings: ConsentDebugSettings(
        debugGeography: DebugGeography.debugGeographyEea,
        testIdentifiers: _debugTestDeviceIds
            .split(',')
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toList(),
      ),
    );
  }

  Future<void> _refreshPrivacyOptionsRequired() async {
    final required = await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;
    if (required == _privacyOptionsRequired) return;
    _privacyOptionsRequired = required;
    _notify();
  }

  Future<void> _startSdkIfAllowed() async {
    if (!await ConsentInformation.instance.canRequestAds()) return;
    await (_sdkInitialization ??= _startSdk());
  }

  Future<void> _startSdk() async {
    try {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          maxAdContentRating: MaxAdContentRating.t,
          // TODO(admob): the target-audience/age decision is still open. Once
          // made, set `ageRestrictedTreatment` (child/teen) if needed; left
          // unspecified for now.
        ),
      );
      await MobileAds.instance.initialize();
      _adsAvailable = true;
      _notify();
    } catch (e) {
      // Allow a later attempt (e.g. from showPrivacyOptions).
      _sdkInitialization = null;
      rethrow;
    }
  }

  /// The consent flow can outlive the provider (e.g. in tests).
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
