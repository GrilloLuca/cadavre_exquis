import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/domain/models/auth_error.dart';
import 'package:cadavre_exquisite/domain/models/nickname.dart';
import 'package:cadavre_exquisite/domain/models/private_room.dart';
import 'package:cadavre_exquisite/domain/models/story_notification.dart';
import 'package:cadavre_exquisite/ui/account/view_models/account_view_model.dart';

import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_notification_repository.dart';
import '../../../testing/fakes/repositories/fake_room_repository.dart';
import '../../../testing/fakes/repositories/fake_user_profile_repository.dart';

const _me = 'luca.grillo@gmail.com';

void main() {
  late FakeUserProfileRepository profiles;
  late FakeAuthRepository auth;
  late FakeRoomRepository rooms;
  late FakeNotificationRepository notifications;

  setUp(() {
    profiles = FakeUserProfileRepository();
    auth = FakeAuthRepository(email: _me);
    rooms = FakeRoomRepository();
    notifications = FakeNotificationRepository();
  });

  AccountViewModel create() => AccountViewModel(
        profileRepository: profiles,
        authRepository: auth,
        roomRepository: rooms,
        notificationRepository: notifications,
      );

  group('nickname', () {
    test('loads the stored nickname, which makes it read-only', () async {
      profiles = FakeUserProfileRepository(nicknames: {_me: 'Luca'});
      final viewModel = create();
      expect(viewModel.canEditNickname, isFalse);

      await pumpEventQueue();

      expect(viewModel.nickname, 'Luca');
      expect(viewModel.hasNickname, isTrue);
      expect(viewModel.canEditNickname, isFalse);
    });

    test('a failed load disables the form until a retry works', () async {
      profiles.failWith = Exception('offline');
      final viewModel = create();
      await pumpEventQueue();
      expect(viewModel.nicknameLoadFailed, isTrue);
      expect(viewModel.canEditNickname, isFalse);

      profiles.failWith = null;
      await viewModel.loadNickname.execute();

      expect(viewModel.nicknameLoadFailed, isFalse);
      expect(viewModel.canEditNickname, isTrue);
    });

    test('saving stores it once', () async {
      final viewModel = create();
      await pumpEventQueue();

      await viewModel.saveNickname.execute('Luca');

      expect(viewModel.hasNickname, isTrue);
      expect(await profiles.getNickname(_me), 'Luca');
    });

    test('a nickname set meanwhile is reported and reloaded', () async {
      final viewModel = create();
      await pumpEventQueue();
      await profiles.setNickname(email: _me, nickname: 'Other');

      await viewModel.saveNickname.execute('Luca');
      await pumpEventQueue();

      expect(
          viewModel.saveNickname.error,
          isA<UserProfileException>().having(
              (e) => e.code, 'code', UserProfileErrorCode.nicknameAlreadySet));
      expect(viewModel.nickname, 'Other');
    });

    test('the public name is the valid nickname, else the masked email', () {
      final viewModel = create();

      expect(viewModel.publicName('  Luca  G '), 'Luca G');
      expect(viewModel.publicName('a'), 'lu***');
    });

    test('without a user nothing is loaded', () async {
      auth = FakeAuthRepository();
      final viewModel = create();
      await pumpEventQueue();

      expect(viewModel.email, isNull);
      expect(viewModel.loadNickname.completed, isFalse);
    });
  });

  group('room', () {
    test('follows the room repository and changes it', () {
      final viewModel = create();
      var notified = 0;
      viewModel.addListener(() => notified++);
      const room = PrivateRoom(id: 'friends', name: 'Friends');

      viewModel.enterPrivateRoom(room);
      expect(viewModel.privateRoom, room);
      viewModel.selectLanguage('es');

      expect(viewModel.languageCode, 'es');
      expect(viewModel.privateRoom, isNull);
      expect(rooms.calls, ['enter:friends', 'language:es']);
      expect(notified, 2);
    });
  });

  group('account', () {
    test('deleting asks for the password again, then deletes', () async {
      final viewModel = create();

      await viewModel.deleteAccount.execute('secret');

      expect(viewModel.deleteAccount.value, isTrue);
      expect(auth.isAuthenticated, isFalse);
    });

    test('a wrong password fails and keeps the account', () async {
      final viewModel = create();

      await viewModel.deleteAccount.execute(FakeAuthRepository.wrongPassword);

      expect(
          viewModel.deleteAccount.error,
          isA<AuthException>()
              .having((e) => e.code, 'code', AuthErrorCode.invalidCredentials));
      expect(auth.isAuthenticated, isTrue);
    });

    test('dismissing the Google picker deletes nothing', () async {
      auth.googlePickerConfirms = false;
      final viewModel = create();

      await viewModel.deleteAccount.execute(null);

      expect(viewModel.deleteAccount.value, isFalse);
      expect(auth.isAuthenticated, isTrue);
    });

    test('signs out', () async {
      final viewModel = create();

      await viewModel.signOut.execute();

      expect(viewModel.signOut.completed, isTrue);
      expect(auth.isAuthenticated, isFalse);
    });
  });

  group('notifications', () {
    test('shows the permission and turns notifications on', () async {
      notifications = FakeNotificationRepository(
        permission: NotificationPermission.notDetermined,
      );
      final viewModel = create();
      var notified = 0;
      viewModel.addListener(() => notified++);
      expect(viewModel.notificationPermission,
          NotificationPermission.notDetermined);

      await viewModel.enableNotifications.execute();

      expect(notifications.calls, ['enable']);
      expect(viewModel.notificationPermission, NotificationPermission.granted);
      expect(notified, greaterThan(0));
      viewModel.dispose();
    });

    test('signing out unregisters the device first', () async {
      final viewModel = create();
      var unregisteredBeforeSignOut = false;
      auth.addListener(() {
        // The token can only be removed while the user is signed in.
        unregisteredBeforeSignOut = notifications.calls.contains('unregister');
      });

      await viewModel.signOut.execute();

      expect(notifications.calls, ['unregister']);
      expect(unregisteredBeforeSignOut, isTrue);
      expect(auth.isAuthenticated, isFalse);
    });

    test('deleting the account unregisters the device', () async {
      final viewModel = create();

      await viewModel.deleteAccount.execute('secret');

      expect(notifications.calls, ['unregister']);
    });

    test('a dismissed reauthentication keeps the device registered', () async {
      auth.usesPassword = false;
      auth.googlePickerConfirms = false;
      final viewModel = create();

      await viewModel.deleteAccount.execute(null);

      expect(notifications.calls, isEmpty);
    });
  });
}
