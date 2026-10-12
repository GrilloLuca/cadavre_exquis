import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/age_check/age_check_repository.dart';
import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/room/room_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/domain/models/private_room.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/home/view_models/home_view_model.dart';
import 'package:cadavre_exquisite/ui/home/widgets/home_screen.dart';

import '../../../testing/fakes/repositories/fake_age_check_repository.dart';
import '../../../testing/fakes/repositories/fake_auth_repository.dart';
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
        Provider<UserProfileRepository>(
            create: (_) => FakeUserProfileRepository()),
        Provider<AgeCheckRepository>(create: (_) => FakeAgeCheckRepository()),
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
}
