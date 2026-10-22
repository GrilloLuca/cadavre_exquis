import 'package:cadavre_exquisite/data/repositories/age_check/age_check_repository.dart';
import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/domain/models/age_rules.dart';
import 'package:cadavre_exquisite/data/services/age_signals_source.dart';
import 'package:cadavre_exquisite/domain/models/email_key.dart';

/// The gate's answer for opening a mature story.
enum AgeVerdict {
  /// Let the user in.
  adult,

  /// Keep the user out.
  minor,

  /// Nothing is known yet: show the neutral birth-year screen, store the
  /// answer with [AgeCheckRepository.setBirthYear] and decide with
  /// [AgeRules.isAdult].
  askBirthYear,
}

/// Decides whether a user may open mature stories, combining
/// platform age signals with the birth year stored by [AgeCheckRepository].
///
/// Any minor verdict wins: a stored minor year denies access without asking
/// the platform, and a minor signal overrides a stored adult year. Signal
/// results are never written to Firestore (they change over time and the
/// rules only accept a birth year); definitive ones are cached in memory for
/// the app session so the system sheet does not reappear on every tap.
///
/// The app shares one gate (see `config/dependencies.dart`), which also
/// remembers each user's final verdict for the session ([isSessionAdult],
/// [isSessionMinor]). Everything it remembers is forgotten when
/// [authRepository] reports a sign-out, or on [clearSession].
class AgeGate {
  AgeGate({
    AgeSignalsSource? signals,
    required AgeCheckRepository storage,
    AuthRepository? authRepository,
    this.timeout = defaultTimeout,
    DateTime Function()? clock,
  })  : _signals = signals ?? PluginAgeSignalsSource.shared,
        _storage = storage,
        _auth = authRepository,
        _clock = clock ?? DateTime.now {
    _auth?.addListener(_onAuthChanged);
  }

  /// Long enough for the user to answer a system sheet, short enough that a
  /// silent hang does not block them for good.
  static const Duration defaultTimeout = Duration(seconds: 20);

  final AgeSignalsSource _signals;
  final AgeCheckRepository _storage;
  final AuthRepository? _auth;
  final DateTime Function() _clock;

  /// How long to wait for the platform before falling back to asking.
  final Duration timeout;

  /// Definitive (adult or minor) signals per user (email key) for this
  /// session. [AgeSignal.unavailable] is never stored, so later taps retry.
  final Map<String, AgeSignal> _sessionSignals = {};

  /// Users (email keys) found adult or minor this session, whatever the
  /// source of the verdict.
  final Set<String> _sessionAdults = {};
  final Set<String> _sessionMinors = {};

  /// Forgets everything remembered this session, so mature stories lock
  /// again and the platform is asked afresh.
  void clearSession() {
    _sessionSignals.clear();
    _sessionAdults.clear();
    _sessionMinors.clear();
  }

  void _onAuthChanged() {
    if (!_auth!.isAuthenticated) clearSession();
  }

  /// Whether [email] was found adult this session: their mature stories are
  /// unlocked until sign-out or restart.
  bool isSessionAdult(String email) => _sessionAdults.contains(emailKey(email));

  /// Whether [email] was found minor this session: their mature stories are
  /// unavailable (shown disabled, never opened).
  bool isSessionMinor(String email) => _sessionMinors.contains(emailKey(email));

  /// Remembers the final verdict for [email] for the rest of the session.
  void rememberVerdict(String email, {required bool adult}) {
    final key = emailKey(email);
    (adult ? _sessionAdults : _sessionMinors).add(key);
    (adult ? _sessionMinors : _sessionAdults).remove(key);
  }

  /// Stores the [birthYear] entered on the age screen (write-once, see
  /// [AgeCheckRepository.setBirthYear]) and returns whether it makes [email]
  /// an adult.
  Future<bool> recordBirthYear(String email, int birthYear) async {
    await _storage.setBirthYear(email: email, birthYear: birthYear);
    return AgeRules.isAdult(birthYear, _clock());
  }

  /// The birth year stored for [email], or null if never asked. Quiet: no
  /// platform call and no UI, so it is safe from `initState` (for example,
  /// to show mature stories as unavailable to known minors).
  Future<int?> storedBirthYear(String email) => _storage.getBirthYear(email);

  /// Decides access for [email]. May show a system sheet, so call it only on
  /// an explicit tap. Never writes anything; on [AgeVerdict.askBirthYear]
  /// the caller runs the existing birth-year flow.
  Future<AgeVerdict> resolve(String email) async {
    final birthYear = await storedBirthYear(email);
    final storedAdult =
        birthYear == null ? null : AgeRules.isAdult(birthYear, _clock());
    if (storedAdult == false) return AgeVerdict.minor;

    final signal = await _signal(email);
    if (signal == AgeSignal.minor) return AgeVerdict.minor;
    if (signal == AgeSignal.adult || storedAdult == true) {
      return AgeVerdict.adult;
    }
    return AgeVerdict.askBirthYear;
  }

  Future<AgeSignal> _signal(String email) async {
    final key = emailKey(email);
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

  void dispose() => _auth?.removeListener(_onAuthChanged);
}
