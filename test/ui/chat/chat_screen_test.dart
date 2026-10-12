import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/chat/widgets/chat_screen.dart';

import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_story_repository.dart';

/// Counts how many times the story was locked.
class _CountingStoryRepository extends FakeStoryRepository {
  _CountingStoryRepository({super.stories, super.now});

  int locks = 0;

  @override
  Future<void> lockStory({
    required String storyId,
    required String authorEmail,
  }) {
    locks++;
    return super.lockStory(storyId: storyId, authorEmail: authorEmail);
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 12, 10);

  Story story({String? lockedBy}) => Story(
        id: 's1',
        status: 'incomplete',
        currentPosition: kStoryPositions.first,
        parts: const [],
        lockedBy: lockedBy,
        lockedAt: lockedBy == null ? null : now,
        language: 'it',
      );

  /// Rebuilds the whole app, as a change above the Navigator does.
  late StateSetter rebuildApp;

  /// Pumps a page with an "open" button that pushes the chat screen.
  Future<void> pumpAndOpen(
      WidgetTester tester, FakeStoryRepository stories) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthRepository>(
            create: (_) => FakeAuthRepository(email: 'me@example.com')),
        Provider<StoryRepository>.value(value: stories),
      ],
      child: StatefulBuilder(builder: (context, setState) {
        rebuildApp = setState;
        return MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(story: stories.stories['s1']!),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('writes and sends a part, then closes', (tester) async {
    final stories = FakeStoryRepository(stories: [story()], now: () => now);
    await pumpAndOpen(tester, stories);

    expect(find.byType(ChatScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Once upon a time');
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsNothing);
    expect(stories.stories['s1']!.parts.single.text, 'Once upon a time');
  });

  testWidgets('a story locked by someone else closes with a message',
      (tester) async {
    final stories = FakeStoryRepository(
        stories: [story(lockedBy: 'other@example.com')], now: () => now);
    await pumpAndOpen(tester, stories);

    expect(find.byType(ChatScreen), findsNothing);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.errorStoryLockedByOther), findsOneWidget);
  });

  testWidgets('leaving without sending gives the lock back', (tester) async {
    final stories = FakeStoryRepository(stories: [story()], now: () => now);
    await pumpAndOpen(tester, stories);
    expect(stories.stories['s1']!.lockedBy, 'me@example.com');

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsNothing);
    expect(stories.stories['s1']!.lockedBy, isNull);
  });

  testWidgets('an app rebuild while open keeps the same ViewModel',
      (tester) async {
    // The route's builder runs again when the Navigator's dependencies
    // change; a ViewModel created there would lock the story again and
    // leave the screen listening to the old one.
    final stories =
        _CountingStoryRepository(stories: [story()], now: () => now);
    await pumpAndOpen(tester, stories);

    rebuildApp(() {});
    await tester.pumpAndSettle();
    expect(stories.locks, 1);

    await tester.enterText(find.byType(TextField), 'Once upon a time');
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsNothing);
  });
}
