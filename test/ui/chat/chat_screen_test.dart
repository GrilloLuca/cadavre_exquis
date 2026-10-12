import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/chat/view_models/chat_view_model.dart';
import 'package:cadavre_exquisite/ui/chat/widgets/chat_screen.dart';

import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_story_repository.dart';

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

  /// Pumps a page with an "open" button that pushes the chat screen.
  Future<void> pumpAndOpen(
      WidgetTester tester, FakeStoryRepository stories) async {
    final auth = FakeAuthRepository(email: 'me@example.com');
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  viewModel: ChatViewModel(
                    story: stories.stories['s1']!,
                    storyRepository: stories,
                    authRepository: auth,
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
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
}
