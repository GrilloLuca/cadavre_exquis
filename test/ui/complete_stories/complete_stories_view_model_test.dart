import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/data/services/age_signals_source.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/ui/complete_stories/view_models/complete_stories_view_model.dart';

import '../../../testing/fakes/repositories/fake_age_check_repository.dart';
import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_story_repository.dart';

const _me = 'me@example.com';

class _Source implements AgeSignalsSource {
  _Source(this.signal);

  AgeSignal signal;

  @override
  Future<AgeSignal> check() async => signal;
}

void main() {
  final now = DateTime.utc(2026, 10, 12);

  Story story(String id, {bool? mature = false, String author = 'x@y.it'}) =>
      Story(
        id: id,
        status: 'complete',
        currentPosition: 'epilogo',
        parts: [
          StoryPart(
              position: 'introduzione',
              text: id,
              author: author,
              timestamp: now),
        ],
        mature: mature,
        language: 'en',
      );

  late _Source source;
  late FakeAgeCheckRepository ages;
  late AgeGate gate;

  setUp(() {
    source = _Source(AgeSignal.adult);
    ages = FakeAgeCheckRepository();
    gate = AgeGate(signals: source, storage: ages, clock: () => now);
  });

  Future<CompleteStoriesViewModel> create(List<Story> stories) async {
    final viewModel = CompleteStoriesViewModel(
      storyRepository: FakeStoryRepository(stories: stories),
      authRepository: FakeAuthRepository(email: _me),
      ageGate: gate,
      language: 'en',
      now: () => now,
    );
    await pumpEventQueue();
    return viewModel;
  }

  test('lists my stories first, mature ones locked', () async {
    final viewModel = await create([
      story('other'),
      story('mature', mature: true),
      story('mine', author: _me),
    ]);

    final (:mine, :others) = viewModel.sections;
    expect(mine.map((s) => s.id), ['mine']);
    // Same completion time: the repository orders them by id.
    expect(others.map((s) => s.id), ['mature', 'other']);
    expect(viewModel.isLocked(others.first), isTrue);
    expect(viewModel.isLocked(others.last), isFalse);
  });

  test('an adult signal opens the story and unlocks the session', () async {
    final mature = story('mature', mature: true);
    final viewModel = await create([mature]);

    await viewModel.unlock.execute(mature);

    expect(viewModel.unlock.value!.outcome, UnlockOutcome.open);
    expect(viewModel.isLocked(mature), isFalse);
    expect(viewModel.checkingStoryId, isNull);
  });

  test('a minor signal hides mature stories', () async {
    source.signal = AgeSignal.minor;
    final mature = story('mature', mature: true);
    final viewModel = await create([mature, story('normal')]);

    await viewModel.unlock.execute(mature);

    expect(viewModel.unlock.value!.outcome, UnlockOutcome.minor);
    expect(viewModel.sections.others.map((s) => s.id), ['normal']);
  });

  test('no signal asks the birth year, keeping the check running', () async {
    source.signal = AgeSignal.unavailable;
    final mature = story('mature', mature: true);
    final viewModel = await create([mature]);

    await viewModel.unlock.execute(mature);
    expect(viewModel.unlock.value!.outcome, UnlockOutcome.askBirthYear);
    expect(viewModel.checkingStoryId, 'mature');

    await viewModel.submitBirthYear.execute(1990);

    expect(viewModel.submitBirthYear.value!.outcome, UnlockOutcome.open);
    expect(viewModel.submitBirthYear.value!.story.id, 'mature');
    expect(await ages.getBirthYear(_me), 1990);
    expect(viewModel.checkingStoryId, isNull);
    expect(viewModel.isUnlocked, isTrue);
  });

  test('a minor birth year keeps the story unavailable', () async {
    source.signal = AgeSignal.unavailable;
    final mature = story('mature', mature: true);
    final viewModel = await create([mature]);

    await viewModel.unlock.execute(mature);
    await viewModel.submitBirthYear.execute(2015);

    expect(viewModel.submitBirthYear.value!.outcome, UnlockOutcome.minor);
    expect(viewModel.sections.others, isEmpty);
  });

  test('cancelling the birth year changes nothing', () async {
    source.signal = AgeSignal.unavailable;
    final mature = story('mature', mature: true);
    final viewModel = await create([mature]);

    await viewModel.unlock.execute(mature);
    viewModel.cancelBirthYear();

    expect(viewModel.checkingStoryId, isNull);
    expect(viewModel.isLocked(mature), isTrue);
    expect(await ages.getBirthYear(_me), isNull);
  });

  test('a stored minor never sees mature stories', () async {
    ages = FakeAgeCheckRepository(birthYears: {_me: 2015});
    gate = AgeGate(signals: source, storage: ages, clock: () => now);
    final viewModel = await create([story('mature', mature: true)]);

    expect(viewModel.sections.others, isEmpty);
  });

  test('a failing check reports the error and stops checking', () async {
    final mature = story('mature', mature: true);
    final viewModel = await create([mature]);
    gate = _FailingGate(storage: ages);
    final failing = CompleteStoriesViewModel(
      storyRepository: FakeStoryRepository(stories: [mature]),
      authRepository: FakeAuthRepository(email: _me),
      ageGate: gate,
      language: 'en',
    );
    await pumpEventQueue();

    await failing.unlock.execute(mature);

    expect(failing.unlock.error, isA<StateError>());
    expect(failing.checkingStoryId, isNull);
    expect(viewModel.isLocked(mature), isTrue);
  });
}

class _FailingGate extends AgeGate {
  _FailingGate({required super.storage});

  @override
  Future<AgeVerdict> resolve(String email) async => throw StateError('down');
}
