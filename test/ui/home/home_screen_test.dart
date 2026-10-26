import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/ads/ads_repository.dart';
import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/notification/notification_repository.dart';
import 'package:cadavre_exquisite/data/repositories/room/room_repository.dart';
import 'package:cadavre_exquisite/data/repositories/safety/safety_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/data/services/age_signals_source.dart';
import 'package:cadavre_exquisite/domain/models/ad_placement.dart';
import 'package:cadavre_exquisite/domain/models/private_room.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/models/story_notification.dart';
import 'package:cadavre_exquisite/domain/models/app_config.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/chat/widgets/chat_screen.dart';
import 'package:cadavre_exquisite/ui/core/ui/ad_banner.dart';
import 'package:cadavre_exquisite/ui/home/view_models/home_view_model.dart';
import 'package:cadavre_exquisite/ui/home/widgets/home_screen.dart';

import '../../../testing/fakes/repositories/fake_ads_repository.dart';
import '../../../testing/fakes/repositories/fake_age_check_repository.dart';
import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_notification_repository.dart';
import '../../../testing/fakes/repositories/fake_room_repository.dart';
import '../../../testing/fakes/repositories/fake_safety_repository.dart';
import '../../../testing/fakes/repositories/fake_story_repository.dart';
import '../../../testing/fakes/repositories/fake_user_profile_repository.dart';

/// An [AgeSignalsSource] answering [signal].
class _FixedSource implements AgeSignalsSource {
  _FixedSource(this.signal);

  final AgeSignal signal;

  @override
  Future<AgeSignal> check() async => signal;
}

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
    final viewModel = HomeViewModel(
      roomRepository: rooms,
      adsRepository: FakeAdsRepository(),
    );
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
        ChangeNotifierProvider<AdsRepository>(
            create: (_) => FakeAdsRepository()),
        ChangeNotifierProvider<NotificationRepository>(
            create: (_) => FakeNotificationRepository()),
        ChangeNotifierProvider<SafetyRepository>(
            create: (_) => FakeSafetyRepository()),
        Provider<UserProfileRepository>(
            create: (_) => FakeUserProfileRepository()),
        Provider<AppConfig>.value(value: const AppConfig()),
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
      partReviews: {
        kStoryPositions[0]: PartVerdict.safe,
        kStoryPositions[1]: PartVerdict.safe,
      },
    );
    const tapped = StoryNotification(
      kind: StoryNotificationKind.continued,
      storyId: 'mine',
      title: 'Marta continued one of your stories',
    );

    Future<FakeNotificationRepository> pumpHome(WidgetTester tester,
        {StoryNotification? launch,
        List<Story>? stories,
        AgeSignal signal = AgeSignal.unavailable}) async {
      final notifications =
          FakeNotificationRepository(launchNotification: launch);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthRepository>(
              create: (_) => FakeAuthRepository(email: 'me@example.com')),
          ChangeNotifierProvider<RoomRepository>(
              create: (_) => FakeRoomRepository(languageCode: 'it')),
          Provider<StoryRepository>(
              create: (_) =>
                  FakeStoryRepository(stories: stories ?? [continued])),
          ChangeNotifierProvider<SafetyRepository>(
              create: (_) => FakeSafetyRepository()),
          Provider<UserProfileRepository>(
              create: (_) => FakeUserProfileRepository()),
          Provider<AppConfig>.value(value: const AppConfig()),
          Provider<AgeGate>(
              create: (_) => AgeGate(
                  signals: _FixedSource(signal),
                  storage: FakeAgeCheckRepository())),
          ChangeNotifierProvider<AdsRepository>(
              create: (_) => FakeAdsRepository()),
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

    testWidgets(
        'a story whose last part is under review says so and opens nothing',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final pending = Story(
        id: continued.id,
        status: continued.status,
        currentPosition: continued.currentPosition,
        parts: continued.parts,
        language: continued.language,
        partReviews: {kStoryPositions[0]: PartVerdict.safe},
      );
      final notifications = await pumpHome(tester, stories: [pending]);

      notifications.tap(tapped);
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsNothing);
      expect(find.text(l10n.storyUnderReviewError), findsOneWidget);
    });

    testWidgets('a mature story goes through the age check; an adult writes it',
        (tester) async {
      final mature = Story(
        id: continued.id,
        status: continued.status,
        currentPosition: continued.currentPosition,
        parts: continued.parts,
        language: continued.language,
        partReviews: continued.partReviews,
        mature: true,
      );
      final notifications =
          await pumpHome(tester, stories: [mature], signal: AgeSignal.adult);

      notifications.tap(tapped);
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsOneWidget);
    });
  });

  testWidgets(
      'the home starts the ads; the banner is only on the '
      'complete stories tab', (tester) async {
    // Ads available but no unit id: no real ad is ever requested.
    final ads = FakeAdsRepository(available: true);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthRepository>(
            create: (_) => FakeAuthRepository(email: 'me@example.com')),
        ChangeNotifierProvider<RoomRepository>(
            create: (_) => FakeRoomRepository(languageCode: 'it')),
        Provider<StoryRepository>(create: (_) => FakeStoryRepository()),
        ChangeNotifierProvider<NotificationRepository>(
            create: (_) => FakeNotificationRepository()),
        ChangeNotifierProvider<AdsRepository>.value(value: ads),
        ChangeNotifierProvider<SafetyRepository>(
            create: (_) => FakeSafetyRepository()),
        Provider<UserProfileRepository>(
            create: (_) => FakeUserProfileRepository()),
        Provider<AppConfig>.value(value: const AppConfig()),
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
    expect(ads.calls, ['initialize']);
    expect(find.byType(AdBanner), findsNothing);

    await tester.tap(find.byIcon(Icons.menu_book));
    await tester.pumpAndSettle();
    expect(find.byType(AdBanner), findsOneWidget);
    expect(ads.requested, [AdPlacement.completeStoriesBanner]);

    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();
    expect(find.byType(AdBanner), findsNothing);
  });

  testWidgets(
      'switching bottom tab closes the search keyboard and keeps the search',
      (tester) async {
    Story complete(String id, String title) => Story(
          id: id,
          status: 'complete',
          currentPosition: kStoryPositions.last,
          parts: [
            StoryPart(
              position: kStoryPositions.first,
              text: 'text of $id',
              author: 'someone@example.com',
              timestamp: DateTime.utc(2026, 10, 1),
            ),
          ],
          language: 'it',
          title: title,
          mature: false,
          reviewedAt: DateTime.utc(2026, 10, 1),
        );
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthRepository>(
            create: (_) => FakeAuthRepository(email: 'me@example.com')),
        ChangeNotifierProvider<RoomRepository>(
            create: (_) => FakeRoomRepository(languageCode: 'it')),
        Provider<StoryRepository>(
            create: (_) => FakeStoryRepository(stories: [
                  complete('a', 'The lighthouse'),
                  complete('b', 'The dragon'),
                ])),
        ChangeNotifierProvider<NotificationRepository>(
            create: (_) => FakeNotificationRepository()),
        ChangeNotifierProvider<AdsRepository>(
            create: (_) => FakeAdsRepository()),
        ChangeNotifierProvider<SafetyRepository>(
            create: (_) => FakeSafetyRepository()),
        Provider<UserProfileRepository>(
            create: (_) => FakeUserProfileRepository()),
        Provider<AppConfig>.value(value: const AppConfig()),
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
    const field = ValueKey('storySearchField');
    bool fieldFocused() => tester
        .widget<EditableText>(find.descendant(
            of: find.byKey(field, skipOffstage: false),
            matching: find.byType(EditableText, skipOffstage: false),
            skipOffstage: false))
        .focusNode
        .hasFocus;

    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(field), 'dragon');
    await tester.pump();
    expect(find.text('The lighthouse'), findsNothing);
    expect(fieldFocused(), isTrue);

    await tester.tap(find.text('Incomplete'));
    await tester.pumpAndSettle();
    expect(fieldFocused(), isFalse);

    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();
    expect(find.text('dragon'), findsOneWidget);
    expect(find.text('The dragon'), findsOneWidget);
    expect(find.text('The lighthouse'), findsNothing);
    expect(fieldFocused(), isFalse);
  });
}
