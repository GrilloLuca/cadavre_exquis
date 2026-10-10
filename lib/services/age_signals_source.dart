import 'package:age_range_signals/age_range_signals.dart';
import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/services/age_check_service.dart';

/// What the platform says about the current user's age, reduced to the only
/// question the app asks: may they read mature stories?
enum AgeSignal {
  /// The platform reports the user is 18 or older.
  adult,

  /// The platform reports the user is under 18, or the account is
  /// parent-managed.
  minor,

  /// No usable answer: unsupported platform, access not shared, declined,
  /// unknown, an error or a timeout. The caller falls back to asking.
  unavailable,
}

/// A source of platform age signals (Play Age Signals on Android, Declared
/// Age Range on iOS 26+). Kept behind an interface so the pre-1.0 plugin is
/// isolated in one file and the gate logic can be tested with a fake.
abstract class AgeSignalsSource {
  /// Asks the platform for the user's age. May show a system sheet, so call
  /// it only in response to an explicit user action. Never throws: any
  /// failure is reported as [AgeSignal.unavailable].
  Future<AgeSignal> check();
}

/// [AgeSignalsSource] backed by the `age_range_signals` plugin.
class PluginAgeSignalsSource implements AgeSignalsSource {
  /// [plugin] and [isSupportedPlatform] are injectable for tests only.
  PluginAgeSignalsSource({AgeRangeSignals? plugin, bool? isSupportedPlatform})
      : _plugin = plugin ?? AgeRangeSignals.instance,
        _isSupportedPlatform = isSupportedPlatform ??
            (!kIsWeb &&
                (defaultTargetPlatform == TargetPlatform.android ||
                    defaultTargetPlatform == TargetPlatform.iOS));

  /// Shared instance, so the plugin (itself a singleton) is initialized at
  /// most once per app run no matter how many gates are created.
  static final PluginAgeSignalsSource shared = PluginAgeSignalsSource();

  /// The only gate the app cares about. iOS requires gates; on Android the
  /// highest gate is the bar for `verified`.
  static const List<int> ageGates = [18];

  final AgeRangeSignals _plugin;
  final bool _isSupportedPlatform;
  Future<void>? _initialization;

  /// Set once the platform says signals can't be served on this device:
  /// not available for this account or region (e.g. Declared Age Range in
  /// Italy), an OS too old, or a build without the entitlement. None of
  /// these changes while the app runs, so asking again would only show
  /// Apple's sheet again before the birth-year fallback on every tap.
  bool _permanentlyUnavailable = false;

  static bool _isPermanent(Object error) =>
      error is ApiNotAvailableException ||
      error is UnsupportedPlatformException ||
      error is MissingEntitlementException;

  /// Initializes the plugin lazily, on the first check rather than at app
  /// start, so users who never open the section never touch the API. A
  /// failed initialization is forgotten so the next check retries it.
  Future<void> _ensureInitialized() {
    return _initialization ??=
        _plugin.initialize(ageGates: ageGates).catchError((Object error) {
      _initialization = null;
      throw error;
    });
  }

  @override
  Future<AgeSignal> check() async {
    if (!_isSupportedPlatform || _permanentlyUnavailable) {
      return AgeSignal.unavailable;
    }
    try {
      await _ensureInitialized();
      final access = await _plugin.requestAgeSignalsAccess();
      if (access != AgeSignalsAccessStatus.shared) {
        _debugLog('access $access');
        return mapSignal(access, null);
      }
      final result = await _plugin.checkAgeSignals();
      final signal = mapSignal(access, result);
      _debugLog('status ${result.status}, ageLower ${result.ageLower}, '
          'source ${result.ageRangeSource} -> $signal');
      return signal;
    } catch (error) {
      // Every plugin failure (unsupported OS, missing entitlement, Play
      // Services, network, cancellation, ...) means "ask the user instead".
      _debugLog('error $error');
      if (_isPermanent(error)) _permanentlyUnavailable = true;
      return AgeSignal.unavailable;
    }
  }

  /// Logs what the platform answered, in debug builds only: the result is
  /// personal data, and in release a silent fallback is the intended
  /// behaviour.
  static void _debugLog(String message) {
    if (kDebugMode) debugPrint('[AgeSignals] $message');
  }

  /// Maps raw plugin output to an [AgeSignal]. Pure, so it is tested without
  /// the plugin.
  ///
  /// Any hint of a minor wins over everything else: a supervised status, a
  /// parent-managed Android account (`tierB`, even when its band is 18+) or a
  /// lower bound under 18. Only a `verified` status whose lower bound is
  /// known to be 18+ counts as adult; a `verified` result without a lower
  /// bound is treated as unavailable rather than trusted blindly.
  static AgeSignal mapSignal(
    AgeSignalsAccessStatus access,
    AgeSignalsResult? result,
  ) {
    if (access != AgeSignalsAccessStatus.shared || result == null) {
      return AgeSignal.unavailable;
    }
    final ageLower = result.ageLower;
    final isMinor = _minorStatuses.contains(result.status) ||
        result.ageRangeSource == AgeRangeSource.tierB ||
        (ageLower != null && ageLower < AgeCheckService.adultAge);
    if (isMinor) return AgeSignal.minor;
    if (result.status == AgeSignalsStatus.verified &&
        ageLower != null &&
        ageLower >= AgeCheckService.adultAge) {
      return AgeSignal.adult;
    }
    return AgeSignal.unavailable;
  }

  static const Set<AgeSignalsStatus> _minorStatuses = {
    AgeSignalsStatus.supervised,
    AgeSignalsStatus.supervisedApprovalPending,
    AgeSignalsStatus.supervisedApprovalDenied,
  };
}
