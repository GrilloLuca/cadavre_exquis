import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/services/age_check_service.dart';
import 'package:cadavre_exquisite/services/age_gate.dart';
import 'package:cadavre_exquisite/services/age_signals_source.dart';

class _FakeSource implements AgeSignalsSource {
  _FakeSource(this._answer);

  final Future<AgeSignal> Function() _answer;
  int calls = 0;

  factory _FakeSource.value(AgeSignal signal) =>
      _FakeSource(() async => signal);

  @override
  Future<AgeSignal> check() {
    calls++;
    return _answer();
  }
}

const email = 'Luca@Example.com';
final now = DateTime(2026, 10, 9);
const adultYear = 1990;
const minorYear = 2012;

void main() {
  late FakeFirebaseFirestore firestore;
  late AgeCheckService storage;

  setUp(() {
    AgeGate.clearSessionCache();
    firestore = FakeFirebaseFirestore();
    storage = AgeCheckService(firestore: firestore);
  });

  AgeGate gate(AgeSignalsSource source, {Duration? timeout}) => AgeGate(
        signals: source,
        storage: storage,
        clock: () => now,
        timeout: timeout ?? AgeGate.defaultTimeout,
      );

  /// Every stored age check, by document id. Queried rather than dumped:
  /// the fake records an empty placeholder for any document merely read.
  Future<Map<String, Map<String, dynamic>>> ageChecks() async {
    final snapshot = await firestore.collection('ageChecks').get();
    return {for (final doc in snapshot.docs) doc.id: doc.data()};
  }

  /// Resolves and asserts no age check was created or changed.
  Future<AgeVerdict> resolveWithoutWrites(AgeGate gate) async {
    final before = await ageChecks();
    final verdict = await gate.resolve(email);
    expect(await ageChecks(), before, reason: 'signals must not be persisted');
    return verdict;
  }

  group('decision table', () {
    test('stored minor -> minor, source not called', () async {
      await storage.setBirthYear(email: email, birthYear: minorYear);
      final source = _FakeSource.value(AgeSignal.adult);

      expect(await resolveWithoutWrites(gate(source)), AgeVerdict.minor);
      expect(source.calls, 0);
    });

    test('stored adult + signal adult -> adult', () async {
      await storage.setBirthYear(email: email, birthYear: adultYear);
      final source = _FakeSource.value(AgeSignal.adult);

      expect(await resolveWithoutWrites(gate(source)), AgeVerdict.adult);
      expect(source.calls, 1);
    });

    test('stored adult + signal unavailable -> adult', () async {
      await storage.setBirthYear(email: email, birthYear: adultYear);

      expect(
        await resolveWithoutWrites(
            gate(_FakeSource.value(AgeSignal.unavailable))),
        AgeVerdict.adult,
      );
    });

    test('stored adult + signal minor -> minor', () async {
      await storage.setBirthYear(email: email, birthYear: adultYear);

      expect(
        await resolveWithoutWrites(gate(_FakeSource.value(AgeSignal.minor))),
        AgeVerdict.minor,
      );
    });

    test('none + signal adult -> adult, nothing written', () async {
      expect(
        await resolveWithoutWrites(gate(_FakeSource.value(AgeSignal.adult))),
        AgeVerdict.adult,
      );
      expect(await storage.getBirthYear(email), isNull);
    });

    test('none + signal minor -> minor, nothing written', () async {
      expect(
        await resolveWithoutWrites(gate(_FakeSource.value(AgeSignal.minor))),
        AgeVerdict.minor,
      );
      expect(await storage.getBirthYear(email), isNull);
    });

    test('none + signal unavailable -> askBirthYear', () async {
      expect(
        await resolveWithoutWrites(
            gate(_FakeSource.value(AgeSignal.unavailable))),
        AgeVerdict.askBirthYear,
      );
    });

    test('born 2008 is still a minor in 2026 (year-only rule)', () async {
      await storage.setBirthYear(email: email, birthYear: 2008);
      final source = _FakeSource.value(AgeSignal.adult);

      expect(await gate(source).resolve(email), AgeVerdict.minor);
      expect(source.calls, 0);
    });
  });

  group('failures', () {
    test('timeout with no stored year -> askBirthYear', () async {
      final never = _FakeSource(() => Completer<AgeSignal>().future);

      expect(
        await gate(never, timeout: const Duration(milliseconds: 10))
            .resolve(email),
        AgeVerdict.askBirthYear,
      );
    });

    test('timeout with stored adult -> adult', () async {
      await storage.setBirthYear(email: email, birthYear: adultYear);
      final never = _FakeSource(() => Completer<AgeSignal>().future);

      expect(
        await gate(never, timeout: const Duration(milliseconds: 10))
            .resolve(email),
        AgeVerdict.adult,
      );
    });

    test('a throwing source with no stored year -> askBirthYear', () async {
      final broken = _FakeSource(() => Future.error(StateError('boom')));

      expect(await gate(broken).resolve(email), AgeVerdict.askBirthYear);
    });

    test('a throwing source with stored adult -> adult', () async {
      await storage.setBirthYear(email: email, birthYear: adultYear);
      final broken = _FakeSource(() => throw StateError('boom'));

      expect(await gate(broken).resolve(email), AgeVerdict.adult);
    });

    test('defaults to a 20 second timeout', () {
      expect(
          AgeGate(signals: _FakeSource.value(AgeSignal.adult), storage: storage)
              .timeout,
          const Duration(seconds: 20));
    });
  });

  group('session cache', () {
    test('adult is cached across gates for the same user', () async {
      final source = _FakeSource.value(AgeSignal.adult);

      expect(await gate(source).resolve(email), AgeVerdict.adult);
      expect(await gate(source).resolve('luca@example.com'), AgeVerdict.adult);
      expect(source.calls, 1);
    });

    test('minor is cached', () async {
      final source = _FakeSource.value(AgeSignal.minor);

      expect(await gate(source).resolve(email), AgeVerdict.minor);
      expect(await gate(source).resolve(email), AgeVerdict.minor);
      expect(source.calls, 1);
    });

    test('unavailable is not cached, so the next tap retries', () async {
      var signal = AgeSignal.unavailable;
      final source = _FakeSource(() async => signal);
      final g = gate(source);

      expect(await g.resolve(email), AgeVerdict.askBirthYear);
      signal = AgeSignal.adult;
      expect(await g.resolve(email), AgeVerdict.adult);
      expect(source.calls, 2);
    });

    test('a timeout is not cached', () async {
      var hang = true;
      final source = _FakeSource(() =>
          hang ? Completer<AgeSignal>().future : Future.value(AgeSignal.minor));
      final g = gate(source, timeout: const Duration(milliseconds: 10));

      expect(await g.resolve(email), AgeVerdict.askBirthYear);
      hang = false;
      expect(await g.resolve(email), AgeVerdict.minor);
      expect(source.calls, 2);
    });

    test('the cache is per user', () async {
      final source = _FakeSource.value(AgeSignal.adult);

      await gate(source).resolve(email);
      await gate(source).resolve('someone@else.com');
      expect(source.calls, 2);
    });

    test('a cached minor signal overrides a stored adult year', () async {
      await gate(_FakeSource.value(AgeSignal.minor)).resolve(email);
      await storage.setBirthYear(email: email, birthYear: adultYear);

      expect(
        await gate(_FakeSource.value(AgeSignal.adult)).resolve(email),
        AgeVerdict.minor,
      );
    });
  });

  test('storedBirthYear reads quietly without calling the source', () async {
    final source = _FakeSource.value(AgeSignal.adult);
    final g = gate(source);

    expect(await g.storedBirthYear(email), isNull);
    await storage.setBirthYear(email: email, birthYear: adultYear);
    expect(await g.storedBirthYear(email), adultYear);
    expect(source.calls, 0);
  });
}
