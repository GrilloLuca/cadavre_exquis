import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/data/services/age_signals_source.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/ui/core/view_models/mature_story_access.dart';

import '../../../../testing/fakes/repositories/fake_age_check_repository.dart';
import '../../../../testing/fakes/repositories/fake_auth_repository.dart';

const _me = 'me@example.com';

class _Source implements AgeSignalsSource {
  _Source(this.signal);

  AgeSignal signal;
  int calls = 0;

  @override
  Future<AgeSignal> check() async {
    calls++;
    return signal;
  }
}

/// An [AgeGate] counting its [resolve] calls, whose quiet stored-year read
/// waits for [read] when given.
class _CountingGate extends AgeGate {
  _CountingGate({required super.signals, required super.storage, super.clock});

  int resolves = 0;
  Future<int?>? read;

  @override
  Future<AgeVerdict> resolve(String email) {
    resolves++;
    return super.resolve(email);
  }

  @override
  Future<int?> storedBirthYear(String email) =>
      read ?? super.storedBirthYear(email);
}

void main() {
  final now = DateTime.utc(2026, 10, 22);

  Story story(String id, {bool? mature}) => Story(
        id: id,
        status: 'complete',
        currentPosition: 'epilogo',
        parts: const [],
        mature: mature,
      );

  final mature = story('mature', mature: true);
  final cleared = story('cleared', mature: false);
  final unjudged = story('unjudged');

  late _Source source;
  late FakeAgeCheckRepository ages;
  late _CountingGate gate;
  late FakeAuthRepository auth;
  late int changes;

  setUp(() {
    source = _Source(AgeSignal.adult);
    ages = FakeAgeCheckRepository();
    auth = FakeAuthRepository(email: _me);
    changes = 0;
  });

  MatureStoryAccess create({bool visibleToMinors = true}) {
    gate = _CountingGate(signals: source, storage: ages, clock: () => now);
    return MatureStoryAccess(
      ageGate: gate,
      authRepository: auth,
      now: () => now,
      onChanged: () => changes++,
      visibleToMinors: visibleToMinors,
    );
  }

  test('mature stories are visible to minors by default', () {
    expect(create().visibleToMinors, isTrue);
  });

  test('a story that is not mature is none, whatever the age', () async {
    ages = FakeAgeCheckRepository(birthYears: {_me: 2015});
    final access = create();
    await access.loadBirthYear();

    expect(access.stateOf(cleared), MatureTileState.none);
    expect(access.stateOf(unjudged), MatureTileState.none);
  });

  test('unknown age: locked', () async {
    final access = create();
    await access.loadBirthYear();

    expect(access.isKnownMinor, isFalse);
    expect(access.stateOf(mature), MatureTileState.locked);
    expect(changes, 1);
  });

  test('a stored adult year alone stays locked (a signal may say minor)',
      () async {
    ages = FakeAgeCheckRepository(birthYears: {_me: 1990});
    final access = create();
    await access.loadBirthYear();

    expect(access.stateOf(mature), MatureTileState.locked);
  });

  test('while the stored-year read runs, a stored minor is still locked',
      () async {
    ages = FakeAgeCheckRepository(birthYears: {_me: 2015});
    final read = Completer<int?>();
    final access = create();
    gate.read = read.future;
    final loading = access.loadBirthYear();

    expect(access.stateOf(mature), MatureTileState.locked);

    read.complete(2015);
    await loading;
    expect(access.stateOf(mature), MatureTileState.unavailable);
  });

  test('a failed read leaves the age unknown', () async {
    final access = create();
    gate.read = Future.error(StateError('offline'));
    await access.loadBirthYear();

    expect(access.stateOf(mature), MatureTileState.locked);
    expect(changes, 1);
  });

  test(
      'a stored minor year: unavailable, and unlock answers minor without '
      'calling the gate', () async {
    ages = FakeAgeCheckRepository(birthYears: {_me: 2015});
    final access = create();
    await access.loadBirthYear();

    expect(access.isKnownMinor, isTrue);
    expect(access.stateOf(mature), MatureTileState.unavailable);

    final result = await access.unlock(mature);

    expect(result.outcome, UnlockOutcome.minor);
    expect(gate.resolves, 0);
    expect(source.calls, 0);
  });

  test('a session minor verdict turns every mature story unavailable',
      () async {
    source.signal = AgeSignal.minor;
    final access = create();
    await access.loadBirthYear();
    final other = story('other', mature: true);

    final result = await access.unlock(mature);

    expect(result.outcome, UnlockOutcome.minor);
    expect(access.stateOf(mature), MatureTileState.unavailable);
    expect(access.stateOf(other), MatureTileState.unavailable);
    expect(access.checkingStoryId, isNull);

    // Shared through the gate: a second helper (another list) knows too.
    final second = MatureStoryAccess(
        ageGate: gate, authRepository: auth, onChanged: () {});
    expect(second.stateOf(other), MatureTileState.unavailable);
    expect((await second.unlock(other)).outcome, UnlockOutcome.minor);
    expect(gate.resolves, 1);
  });

  test('an adult verdict unlocks every mature story for the session', () async {
    final access = create();
    await access.loadBirthYear();

    final result = await access.unlock(mature);

    expect(result.outcome, UnlockOutcome.open);
    expect(access.isSessionAdult, isTrue);
    expect(
        access.stateOf(story('other', mature: true)), MatureTileState.unlocked);
  });

  test('the check is marked running, and other taps are ignored meanwhile',
      () async {
    source.signal = AgeSignal.unavailable;
    final access = create();
    await access.loadBirthYear();

    final first = await access.unlock(mature);
    expect(first.outcome, UnlockOutcome.askBirthYear);
    expect(access.checkingStoryId, 'mature');
    expect(access.awaitingBirthYear, same(mature));
    expect((await access.unlock(story('other', mature: true))).outcome,
        UnlockOutcome.ignored);

    final second = await access.submitBirthYear(2015);

    expect(second.outcome, UnlockOutcome.minor);
    expect(second.story, same(mature));
    expect(access.checkingStoryId, isNull);
    expect(access.stateOf(mature), MatureTileState.unavailable);
  });

  test('cancelling the birth year changes nothing', () async {
    source.signal = AgeSignal.unavailable;
    final access = create();
    await access.unlock(mature);

    access.cancelBirthYear();

    expect(access.checkingStoryId, isNull);
    expect(access.awaitingBirthYear, isNull);
    expect(access.stateOf(mature), MatureTileState.locked);
  });

  test('without a user nothing is checked', () async {
    auth = FakeAuthRepository();
    final access = create();
    await access.loadBirthYear();

    expect((await access.unlock(mature)).outcome, UnlockOutcome.ignored);
    expect(access.stateOf(mature), MatureTileState.locked);
    expect(gate.resolves, 0);
  });

  test('does not notify once disposed', () async {
    final read = Completer<int?>();
    final access = create();
    gate.read = read.future;
    final loading = access.loadBirthYear();

    access.dispose();
    read.complete(null);
    await loading;

    expect(changes, 0);
  });

  group('hidden from minors (visibleToMinors false)', () {
    test('a stored minor year: hidden, unlock still answers minor', () async {
      ages = FakeAgeCheckRepository(birthYears: {_me: 2015});
      final access = create(visibleToMinors: false);
      await access.loadBirthYear();

      expect(access.stateOf(mature), MatureTileState.hidden);
      expect(access.isListed(mature), isFalse);
      expect(access.stateOf(cleared), MatureTileState.none);
      expect(access.isListed(cleared), isTrue);
      expect((await access.unlock(mature)).outcome, UnlockOutcome.minor);
      expect(gate.resolves, 0);
    });

    test('while the stored-year read runs, a stored minor is locked',
        () async {
      ages = FakeAgeCheckRepository(birthYears: {_me: 2015});
      final read = Completer<int?>();
      final access = create(visibleToMinors: false);
      gate.read = read.future;
      final loading = access.loadBirthYear();

      expect(access.stateOf(mature), MatureTileState.locked);
      expect(access.isListed(mature), isTrue);

      read.complete(2015);
      await loading;
      expect(access.stateOf(mature), MatureTileState.hidden);
    });

    test('a session minor verdict hides every mature story', () async {
      source.signal = AgeSignal.minor;
      final access = create(visibleToMinors: false);
      await access.loadBirthYear();
      final other = story('other', mature: true);
      final before = changes;

      final result = await access.unlock(mature);

      expect(result.outcome, UnlockOutcome.minor);
      expect(access.stateOf(mature), MatureTileState.hidden);
      expect(access.stateOf(other), MatureTileState.hidden);
      // The owner is told, so the View drops the tiles.
      expect(changes, greaterThan(before));
    });

    test('unknown age and session adults are as with the flag on', () async {
      final access = create(visibleToMinors: false);
      await access.loadBirthYear();
      expect(access.stateOf(mature), MatureTileState.locked);

      await access.unlock(mature);
      expect(access.stateOf(mature), MatureTileState.unlocked);
    });
  });
}
