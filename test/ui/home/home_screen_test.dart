import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/notification/notification_repository.dart';
import 'package:cadavre_exquisite/data/repositories/room/room_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/domain/models/private_room.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/models/story_notification.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/chat/widgets/chat_screen.dart';
import 'package:cadavre_exquisite/ui/home/view_models/home_view_model.dart';
import 'package:cadavre_exquisite/ui/home/widgets/home_screen.dart';

import '../../../testing/fakes/repositories/fake_age_check_repository.dart';
import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_notification_repository.dart';
import '../../../testing/fakes/repositories/fake_room_repository.dart';
import '../../../testing/fakes/repositories/fake_story_repository.dart';
import '../../../testing/fakes/repositories/fake_user_profile_repository.dart';

void main() {
  const friends = PrivateRoom(id: 'friends', name: 'Friends');

  Story incomplete(String id, {String language = 'it', String? roomId}) =>
      Story(
        id: id,
        status: 'incomplete',
        currentPosition: kStoryPositions.first,
        parts: const [],
        language: language,
        roomId: roomId,
      );

  test('HomeViewModel follows the room repository', () {
    final rooms = FakeRoomRepository(languageCode: 'es');
    final viewModel = HomeViewModel(roomRepository: rooms);
    var notified = 0;
    viewModel.addListener(() => notified++);

    expect(viewModel.language!.code, 'es');
    rooms.enterPrivateRoom(friends);

    expect(viewModel.privateRoom, friends);
    expect(notified, 1);
    viewModel.dispose();
  });

  testWidgets('the incomplete stories tab follows room changes',
      (tester) async {
    final rooms = FakeRoomRepository(languageCode: 'it');
    final stories = FakeStoryRepository(stories: [
      incomplete('public 1'),
      incomplete('public 2'),
      incomplete('private', roomId: 'friends'),
    ]);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthRepository>(
            create: (_) => FakeAuthRepository(email: 'me@example.com')),
        ChangeNotifierProvider<RoomRepository>.value(value: rooms),
        Provider<StoryRepository>.value(value: stories),
        ChangeNotifierProvider<NotificationRepository>(
            create: (_) => FakeNotificationRepository()),
        Provider<UserProfileRepository>(
            create: (_) => FakeUserProfileRepository()),
        Provider<AgeGate>(
            create: (_) => AgeGate(storage: FakeAgeCheckRepository())),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: HomeScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    // The two stories of the public Italian room.
    expect(find.byType(ListTile), findsNWidgets(2));
    expect(find.byTooltip('Room: Italiano. Change it in Profile.'),
        findsOneWidget);

    rooms.enterPrivateRoom(friends);
    await tester.pumpAndSettle();

    // Only the private room's story.
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('Friends'), findsOneWidget);
  });

  group('notifications', () {
    final continued = Story(
      id: 'mine',
      status: 'incomplete',
      currentPosition: kStoryPositions[2],
      parts: [
        for (final (i, author)
            in ['me@example.com', 'other@example.com'].indexed)
          StoryPart(
            position: kStoryPositions[i],
            text: 'part $i',
            author: author,
            timestamp: DateTime.utc(2026, 10, 1),
          ),
      ],
      language: 'en',
    );
    const tapped = StoryNotification(
      kind: StoryNotificationKind.continued,
      storyId: 'mine',
      title: 'Marta continued one of your stories',
    );

    Future<FakeNotificationRepository> pumpHome(WidgetTester tester,
        {StoryNotification? launch}) async {
      final notifications =
          FakeNotificationRepository(launchNotification: launch);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthRepository>(
              create: (_) => FakeAuthRepository(email: 'me@example.com')),
          ChangeNotifierProvider<RoomRepository>(
              create: (_) => FakeRoomRepository(languageCode: 'it')),
          Provider<StoryRepository>(
              create: (_) => FakeStoryRepository(stories: [continued])),
          Provider<UserProfileRepository>(
              create: (_) => FakeUserProfileRepository()),
          Provider<AgeGate>(
              create: (_) => AgeGate(storage: FakeAgeCheckRepository())),
          ChangeNotifierProvider<NotificationRepository>.value(
              value: notifications),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: HomeScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      return notifications;
    }

    testWidgets('the notification that launched the app opens its story',
        (tester) async {
      await pumpHome(tester, launch: tapped);

      expect(find.byType(ChatScreen), findsOneWidget);
    });

    testWidgets('a tap in the background opens the story', (tester) async {
      final notifications = await pumpHome(tester);
      expect(find.byType(ChatScreen), findsNothing);

      notifications.tap(tapped);
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsOneWidget);
    });

    testWidgets('a notification in the foreground is offered in a snack bar',
        (tester) async {
      final notifications = await pumpHome(tester);

      notifications.receive(tapped);
      await tester.pumpAndSettle();
      expect(find.text('Marta continued one of your stories'), findsOneWidget);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
    });

    testWidgets('a story that moved on shows why it cannot be opened',
        (tester) async {
      final notifications = await pumpHome(tester);

      notifications.tap(const StoryNotification(
        kind: StoryNotificationKind.continued,
        storyId: 'deleted',
      ));
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsNothing);
      expect(find.text('This story is no longer available.'), findsOneWidget);
    });
  });
}
