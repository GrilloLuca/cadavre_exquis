import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/ui/story_read/view_models/story_read_view_model.dart';

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
    ],
  );

  test('masked authors first, nicknames once loaded', () async {
    final viewModel = StoryReadViewModel(
      story: story,
      profileRepository: FakeUserProfileRepository(
          nicknames: {'mario.rossi@example.com': 'Supermario'}),
    );

    expect(viewModel.authorNameOf(story.parts[0]), 'Ma***');

    await pumpEventQueue();

    expect(viewModel.authorNameOf(story.parts[0]), 'Supermario');
    expect(viewModel.authorNameOf(story.parts[1]), 'lu***');
  });

  test('a failed lookup keeps the masked authors', () async {
    final viewModel = StoryReadViewModel(
        story: story, profileRepository: _ThrowingProfileRepository());
    await pumpEventQueue();

    expect(viewModel.loadNicknames.error, isNull);
    expect(viewModel.authorNameOf(story.parts[0]), 'Ma***');
  });
}
