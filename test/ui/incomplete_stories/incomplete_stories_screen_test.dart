import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/notification/notification_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/chat/widgets/chat_screen.dart';
import 'package:cadavre_exquisite/ui/incomplete_stories/widgets/incomplete_stories_screen.dart';

import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_notification_repository.dart';
import '../../../testing/fakes/repositories/fake_story_repository.dart';
import '../../../testing/fakes/repositories/fake_user_profile_repository.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  Future<void> pump(WidgetTester tester, FakeStoryRepository stories,
      {String? roomId}) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthRepository>(
            create: (_) => FakeAuthRepository(email: 'me@example.com')),
        Provider<StoryRepository>.value(value: stories),
        ChangeNotifierProvider<NotificationRepository>(
            create: (_) => FakeNotificationRepository()),
        Provider<UserProfileRepository>(
            create: (_) => FakeUserProfileRepository()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: IncompleteStoriesScreen(language: 'it', roomId: roomId),
      ),
    ));
    // Not pumpAndSettle: the typing indicator of a locked story animates
    // forever. One more frame delivers the first list.
    await tester.pump();
  }

  testWidgets('shows a message when the room has no stories', (tester) async {
    await pump(tester, FakeStoryRepository());

    expect(find.text(l10n.noIncompleteStories), findsOneWidget);
  });

  testWidgets('a story being written by someone else is disabled',
      (tester) async {
    final stories = FakeStoryRepository(stories: [
      Story(
        id: 's1',
        status: 'incomplete',
        currentPosition: kStoryPositions.first,
        parts: const [],
        lockedBy: 'other@example.com',
        lockedAt: DateTime.now(),
      ),
    ]);
    await pump(tester, stories);

    expect(find.text(l10n.storyBeingWritten), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ChatScreen), findsNothing);
  });

  testWidgets('the new story button creates a story and opens it',
      (tester) async {
    final stories = FakeStoryRepository();
    await pump(tester, stories, roomId: 'friends');

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(stories.stories.values.single.roomId, 'friends');
  });

  testWidgets('a failed creation shows an error', (tester) async {
    final stories = FakeStoryRepository()..failWith = Exception('offline');
    await pump(tester, stories);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text(l10n.genericError), findsOneWidget);
    expect(find.byType(ChatScreen), findsNothing);
  });
}
