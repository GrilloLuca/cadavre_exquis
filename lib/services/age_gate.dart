import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/services/age_check_service.dart';
import 'package:cadavre_exquisite/services/age_signals_source.dart';
import 'package:cadavre_exquisite/services/user_profile_service.dart';

/// The gate's answer for the mature-stories section.
enum AgeVerdict {
  /// Let the user in.
  adult,

  /// Keep the user out.
  minor,

  /// Nothing is known yet: show the neutral birth-year screen, store the
  /// answer with [AgeCheckService.setBirthYear] and decide with
  /// [AgeCheckService.isAdult].
  askBirthYear,
}

/// Decides whether a user may open the mature-stories section, combining
/// platform age signals with the birth year stored by [AgeCheckService].
///
/// Any minor verdict wins: a stored minor year denies access without asking
/// the platform, and a minor signal overrides a stored adult year. Signal
/// results are never written to Firestore (they change over time and the
/// rules only accept a birth year); definitive ones are cached in memory for
/// the app session so the system sheet does not reappear on every tap.
class AgeGate {
  AgeGate({
    AgeSignalsSource? signals,
    AgeCheckService? storage,
    this.timeout = defaultTimeout,
    DateTime Function()? clock,
  })  : _signals = signals ?? PluginAgeSignalsSource.shared,
        _storage = storage ?? AgeCheckService(),
        _clock = clock ?? DateTime.now;

  /// Long enough for the user to answer a system sheet, short enough that a
  /// silent hang does not block them for good.
  static const Duration defaultTimeout = Duration(seconds: 20);

  final AgeSignalsSource _signals;
  final AgeCheckService _storage;
  final DateTime Function() _clock;

  /// How long to wait for the platform before falling back to asking.
  final Duration timeout;

  /// Definitive (adult or minor) signals per user for this app session.
  /// Static so it survives the gate being recreated with each widget.
  /// [AgeSignal.unavailable] is never stored, so later taps retry.
  static final Map<String, AgeSignal> _sessionSignals = {};

  /// Clears the session cache. For tests, or for a future sign-out hook.
  @visibleForTesting
  static void clearSessionCache() => _sessionSignals.clear();

  /// The birth year stored for [email], or null if never asked. Quiet: no
  /// platform call and no UI, so it is safe from `initState` (for example,
  /// to hide the entry point from known minors).
  Future<int?> storedBirthYear(String email) => _storage.getBirthYear(email);

  /// Decides access for [email]. May show a system sheet, so call it only on
  /// an explicit tap. Never writes anything; on [AgeVerdict.askBirthYear]
  /// the caller runs the existing birth-year flow.
  Future<AgeVerdict> resolve(String email) async {
    final birthYear = await storedBirthYear(email);
    final storedAdult =
        birthYear == null ? null : AgeCheckService.isAdult(birthYear, _clock());
    if (storedAdult == false) return AgeVerdict.minor;

    final signal = await _signal(email);
    if (signal == AgeSignal.minor) return AgeVerdict.minor;
    if (signal == AgeSignal.adult || storedAdult == true) {
      return AgeVerdict.adult;
    }
    return AgeVerdict.askBirthYear;
  }

  Future<AgeSignal> _signal(String email) async {
    final key = UserProfileService.profileKey(email);
    final cached = _sessionSignals[key];
    if (cached != null) return cached;

    AgeSignal signal;
    try {
      signal = await _signals.check().timeout(
            timeout,
            onTimeout: () => AgeSignal.unavailable,
          );
    } catch (_) {
      // Sources should not throw, but a broken one must not lock anyone out
      // of the fallback.
      signal = AgeSignal.unavailable;
    }
    if (signal != AgeSignal.unavailable) _sessionSignals[key] = signal;
    return signal;
  }
}
