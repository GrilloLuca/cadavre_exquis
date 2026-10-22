import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/data/services/age_signals_source.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/models/story_notification.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/ui/home/view_models/notification_router_view_model.dart';

import '../../../testing/fakes/repositories/fake_age_check_repository.dart';
import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_notification_repository.dart';
import '../../../testing/fakes/repositories/fake_story_repository.dart';

const _me = 'me@example.com';
const _other = 'other@example.com';

class _FixedSource implements AgeSignalsSource {
  _FixedSource(this.signal);

  final AgeSignal signal;

  @override
  Future<AgeSignal> check() async => signal;
}

/// An [AgeGate] counting its [resolve] calls.
class _CountingGate extends AgeGate {
  _CountingGate({required super.signals, required super.storage});

  int resolves = 0;

  @override
  Future<AgeVerdict> resolve(String email) {
    resolves++;
    return super.resolve(email);
  }
}

StoryPart _part(String position, String author) => StoryPart(
      position: position,
      text: 'text',
      author: author,
      timestamp: DateTime.utc(2026, 10, 1),
    );

/// A story whose parts were written by [authors], in order. [reviewed]
/// gives every part a verdict, and a complete story its `reviewedAt`;
/// without it the last part (or the completion review) is pending.
Story _story(
  List<String> authors, {
  String id = 's1',
  String? lockedBy,
  bool? mature,
  bool reviewed = true,
}) {
  final parts = [
    for (final (i, author) in authors.indexed)
      _part(kStoryPositions[i], author),
  ];
  final complete = parts.length == kStoryPositions.length;
  return Story(
    id: id,
    status: complete ? 'complete' : 'incomplete',
    currentPosition:
        complete ? kStoryPositions.last : kStoryPositions[parts.length],
    parts: parts,
    lockedBy: lockedBy,
    lockedAt: lockedBy == null ? null : DateTime.now(),
    mature: mature,
    partReviews: {
      for (final (i, part) in parts.indexed)
        if (reviewed || i < parts.length - 1) part.position: PartVerdict.safe,
    },
    reviewedAt: complete && reviewed ? DateTime.utc(2026, 10, 2) : null,
  );
}

const _continued =
    StoryNotification(kind: StoryNotificationKind.continued, storyId: 's1');
const _completed =
    StoryNotification(kind: StoryNotificationKind.completed, storyId: 's1');

void main() {
  late FakeNotificationRepository notifications;
  late FakeAuthRepository auth;
  late FakeAgeCheckRepository ages;
  late _CountingGate gate;
  AgeSignal signal = AgeSignal.unavailable;

  /// A birth year that makes the user a minor today.
  final minorYear = DateTime.now().year - 10;

  setUp(() {
    notifications = FakeNotificationRepository();
    auth = FakeAuthRepository(email: _me);
    ages = FakeAgeCheckRepository();
    signal = AgeSignal.unavailable;
  });

  NotificationRouterViewModel create(List<Story> stories) {
    gate = _CountingGate(signals: _FixedSource(signal), storage: ages);
    return NotificationRouterViewModel(
      notificationRepository: notifications,
      storyRepository: FakeStoryRepository(stories: stories),
      authRepository: auth,
      ageGate: gate,
    );
  }

  Future<StoryLink> open(
    NotificationRouterViewModel viewModel,
    StoryNotification notification,
  ) async {
    await viewModel.open.execute(notification);
    expect(viewModel.open.error, isNull);
    return viewModel.open.value!;
  }

  group('a "continued" notification', () {
    test('opens the story to write when it is free', () async {
      final viewModel = create([
        _story([_me, _other])
      ]);

      final link = await open(viewModel, _continued);

      expect(link.outcome, StoryLinkOutcome.write);
      expect(link.story!.id, 's1');
    });

    test('says why the story can no longer be written', () async {
      final cases = {
        _story([_me, _other, _other, _me]): StoryLinkOutcome.alreadyCompleted,
        _story([_me, _other, _me]): StoryLinkOutcome.alreadyContinued,
        _story([_me, _other], lockedBy: 'third@example.com'):
            StoryLinkOutcome.lockedByOther,
      };
      for (final MapEntry(key: story, value: outcome) in cases.entries) {
        final link = await open(create([story]), _continued);
        expect(link.outcome, outcome, reason: '${story.parts.length} parts');
      }
    });

    test('of a story whose last part is under review says so', () async {
      final link = await open(
          create([
            _story([_me, _other], reviewed: false)
          ]),
          _continued);

      expect(link.outcome, StoryLinkOutcome.underReview);
    });

    test(
        'of a mature story keeps it from a stored minor without the age '
        'check, even while a part is under review', () async {
      ages = FakeAgeCheckRepository(birthYears: {_me: minorYear});
      for (final reviewed in [true, false]) {
        final viewModel = create([
          _story([_me, _other], mature: true, reviewed: reviewed),
        ]);

        final link = await open(viewModel, _continued);

        expect(link.outcome, StoryLinkOutcome.matureUnavailable,
            reason: 'reviewed: $reviewed');
        expect(gate.resolves, 0);
      }
    });

    test('of a mature story keeps it from a session minor without the check',
        () async {
      final viewModel = create([
        _story([_me, _other], mature: true),
      ]);
      gate.rememberVerdict(_me, adult: false);

      expect((await open(viewModel, _continued)).outcome,
          StoryLinkOutcome.matureUnavailable);
      expect(gate.resolves, 0);
    });

    test('of a completed story says so before the minor check', () async {
      ages = FakeAgeCheckRepository(birthYears: {_me: minorYear});
      final viewModel = create([
        _story([_me, _other, _me, _other], mature: true),
      ]);

      expect((await open(viewModel, _continued)).outcome,
          StoryLinkOutcome.alreadyCompleted);
    });

    test('of a mature story asks the birth year; an adult then writes it',
        () async {
      final viewModel = create([
        _story([_me, _other], mature: true),
      ]);

      expect((await open(viewModel, _continued)).outcome,
          StoryLinkOutcome.askBirthYear);
      expect(gate.resolves, 1);
      await viewModel.submitBirthYear.execute(1990);

      expect(viewModel.submitBirthYear.value!.outcome, StoryLinkOutcome.write);
      expect(viewModel.submitBirthYear.value!.story!.id, 's1');
      expect(await ages.getBirthYear(_me), 1990);
    });

    test('of a mature story opens it to write for an adult signal', () async {
      signal = AgeSignal.adult;
      final viewModel = create([
        _story([_me, _other], mature: true),
      ]);

      expect(
          (await open(viewModel, _continued)).outcome, StoryLinkOutcome.write);
      // Remembered: the next tap doesn't ask again.
      expect(
          (await open(viewModel, _continued)).outcome, StoryLinkOutcome.write);
      expect(gate.resolves, 1);
    });

    test('of a mature story keeps it from a minor signal', () async {
      signal = AgeSignal.minor;
      final viewModel = create([
        _story([_me, _other], mature: true),
      ]);

      expect((await open(viewModel, _continued)).outcome,
          StoryLinkOutcome.matureUnavailable);
      expect(gate.isSessionMinor(_me), isTrue);
    });

    test('of a mature story checks the turn rules before the age check',
        () async {
      final viewModel = create([
        _story([_me, _other, _me], mature: true),
      ]);

      expect((await open(viewModel, _continued)).outcome,
          StoryLinkOutcome.alreadyContinued);
      expect(gate.resolves, 0);
    });

    test('of a deleted story says it is gone', () async {
      final link = await open(create([]), _continued);

      expect(link.outcome, StoryLinkOutcome.notFound);
    });

    test('is ignored when nobody is signed in', () async {
      auth = FakeAuthRepository();
      final link = await open(
          create([
            _story([_me, _other])
          ]),
          _continued);

      expect(link.outcome, StoryLinkOutcome.ignored);
    });
  });

  group('a "completed" notification', () {
    test('opens a reviewed story to read', () async {
      final viewModel = create([
        _story([_me, _other, _me, _other], mature: false),
      ]);

      expect(
          (await open(viewModel, _completed)).outcome, StoryLinkOutcome.read);
    });

    test('waits for the review', () async {
      final viewModel = create([
        _story([_me, _other, _me, _other], reviewed: false)
      ]);

      expect((await open(viewModel, _completed)).outcome,
          StoryLinkOutcome.notReadyYet);
    });

    test('waits for the review of a story already flagged by a part', () async {
      final viewModel = create([
        _story([_me, _other, _me, _other], mature: true, reviewed: false)
      ]);

      expect((await open(viewModel, _completed)).outcome,
          StoryLinkOutcome.notReadyYet);
      expect(gate.resolves, 0);
    });

    test('of an incomplete story is not ready yet', () async {
      final viewModel = create([
        _story([_me, _other])
      ]);

      expect((await open(viewModel, _completed)).outcome,
          StoryLinkOutcome.notReadyYet);
    });

    test('of a mature story opens it for adults', () async {
      signal = AgeSignal.adult;
      final viewModel = create([
        _story([_me, _other, _me, _other], mature: true),
      ]);

      expect(
          (await open(viewModel, _completed)).outcome, StoryLinkOutcome.read);
    });

    test('of a mature story keeps it from a stored minor without the check',
        () async {
      ages = FakeAgeCheckRepository(birthYears: {_me: minorYear});
      final viewModel = create([
        _story([_me, _other, _me, _other], mature: true),
      ]);

      expect((await open(viewModel, _completed)).outcome,
          StoryLinkOutcome.matureUnavailable);
      expect(gate.resolves, 0);
    });

    test('of a mature story keeps it from a session minor without the check',
        () async {
      final viewModel = create([
        _story([_me, _other, _me, _other], mature: true),
      ]);
      gate.rememberVerdict(_me, adult: false);

      expect((await open(viewModel, _completed)).outcome,
          StoryLinkOutcome.matureUnavailable);
      expect(gate.resolves, 0);
    });

    test('cancelling the birth year lets a later tap ask again', () async {
      final viewModel = create([
        _story([_me, _other, _me, _other], mature: true),
      ]);
      expect((await open(viewModel, _completed)).outcome,
          StoryLinkOutcome.askBirthYear);

      viewModel.cancelBirthYear();

      expect((await open(viewModel, _completed)).outcome,
          StoryLinkOutcome.askBirthYear);
      expect(gate.resolves, 2);
    });

    test('of a mature story asks the birth year when nothing is known',
        () async {
      final viewModel = create([
        _story([_me, _other, _me, _other], mature: true),
      ]);

      expect((await open(viewModel, _completed)).outcome,
          StoryLinkOutcome.askBirthYear);
      await viewModel.submitBirthYear.execute(1990);

      expect(viewModel.submitBirthYear.value!.outcome, StoryLinkOutcome.read);
      expect(await ages.getBirthYear(_me), 1990);
    });
  });

  test('opens the notification that launched the app', () async {
    notifications.launchNotification = _continued;
    final viewModel = create([
      _story([_me, _other])
    ]);

    await pumpEventQueue();

    expect(viewModel.open.value?.outcome, StoryLinkOutcome.write);
  });

  test('opens a notification tapped in the background', () async {
    final viewModel = create([
      _story([_me, _other])
    ]);

    notifications.tap(_continued);
    await pumpEventQueue();

    expect(viewModel.open.value?.outcome, StoryLinkOutcome.write);
  });

  test('offers a notification received in the foreground once', () async {
    final viewModel = create([]);
    var notified = 0;
    viewModel.addListener(() => notified++);

    notifications.receive(_completed);
    await pumpEventQueue();

    expect(notified, 1);
    expect(viewModel.takeBanner(), same(_completed));
    expect(viewModel.takeBanner(), isNull);
  });

  test('stops listening once disposed', () async {
    final viewModel = create([
      _story([_me, _other])
    ]);
    viewModel.dispose();

    notifications.tap(_continued);
    await pumpEventQueue();
  });
}
