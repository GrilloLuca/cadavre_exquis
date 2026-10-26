import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/domain/models/content_report.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/ui/story_read/view_models/story_read_view_model.dart';

import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_safety_repository.dart';
import '../../../testing/fakes/repositories/fake_user_profile_repository.dart';

/// A repository whose lookup throws, which the contract says shouldn't
/// happen: the screen must still show masked authors.
class _ThrowingProfileRepository extends FakeUserProfileRepository {
  @override
  Future<Map<String, String>> nicknamesFor(Iterable<String> emails) =>
      Future.error(Exception('offline'));
}

void main() {
  final at = DateTime.utc(2026, 10, 12);

  final story = Story(
    id: 's1',
    status: 'complete',
    currentPosition: 'epilogo',
    parts: [
      StoryPart(
          position: 'introduzione',
          text: 'a',
          author: 'Mario.Rossi@example.com',
          timestamp: at),
      StoryPart(
          position: 'sviluppo1',
          text: 'b',
          author: 'luca.grillo@gmail.com',
          timestamp: at),
      // A deleted account's part.
      StoryPart(position: 'sviluppo2', text: 'c', author: '', timestamp: at),
    ],
  );

  late FakeSafetyRepository safety;

  setUp(() => safety = FakeSafetyRepository());

  StoryReadViewModel create({FakeUserProfileRepository? profiles}) =>
      StoryReadViewModel(
        story: story,
        profileRepository: profiles ?? FakeUserProfileRepository(),
        safetyRepository: safety,
        authRepository: FakeAuthRepository(email: 'Luca.Grillo@gmail.com'),
      );

  test('masked authors first, nicknames once loaded', () async {
    final viewModel = create(
      profiles: FakeUserProfileRepository(
          nicknames: {'mario.rossi@example.com': 'Supermario'}),
    );

    expect(viewModel.authorNameOf(story.parts[0]), 'Ma***');

    await pumpEventQueue();

    expect(viewModel.authorNameOf(story.parts[0]), 'Supermario');
    expect(viewModel.authorNameOf(story.parts[1]), 'lu***');
  });

  test('a failed lookup keeps the masked authors', () async {
    final viewModel = create(profiles: _ThrowingProfileRepository());
    await pumpEventQueue();

    expect(viewModel.loadNicknames.error, isNull);
    expect(viewModel.authorNameOf(story.parts[0]), 'Ma***');
  });

  group('safety', () {
    test("only other players' parts can be reported or blocked", () {
      final viewModel = create();

      expect(viewModel.safety.canActOn(story.parts[0]), isTrue);
      // The user's own part, whatever the case of the email.
      expect(viewModel.safety.canActOn(story.parts[1]), isFalse);
      expect(viewModel.safety.canActOn(story.parts[2]), isFalse);
    });

    test('report sends the story, the position and the reason', () async {
      final viewModel = create();

      await viewModel.safety.report
          .execute((part: story.parts[0], reason: ReportReason.harassment));

      expect(viewModel.safety.report.error, isNull);
      expect(safety.reports, [
        (
          storyId: 's1',
          position: 'introduzione',
          reason: ReportReason.harassment
        ),
      ]);
    });

    test('block blocks the author by email key and returns the part', () async {
      final viewModel = create();

      await viewModel.safety.block.execute(story.parts[0]);

      expect(viewModel.safety.block.value, same(story.parts[0]));
      expect(safety.blockedKeys, {'mario.rossi@example.com'});
    });

    test('a failed report surfaces as the command error', () async {
      safety.failWith = Exception('offline');
      final viewModel = create();

      await viewModel.safety.report
          .execute((part: story.parts[0], reason: ReportReason.spam));

      expect(viewModel.safety.report.error, isA<Exception>());
    });
  });
}
