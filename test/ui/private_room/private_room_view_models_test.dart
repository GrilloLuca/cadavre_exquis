import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/domain/models/private_room.dart';
import 'package:cadavre_exquisite/ui/private_room/view_models/create_private_room_view_model.dart';
import 'package:cadavre_exquisite/ui/private_room/view_models/join_private_room_view_model.dart';

import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_private_room_repository.dart';

Matcher _failsWith(PrivateRoomErrorCode code) =>
    isA<PrivateRoomException>().having((e) => e.code, 'code', code);

void main() {
  late FakePrivateRoomRepository rooms;

  setUp(() => rooms = FakePrivateRoomRepository());

  CreatePrivateRoomViewModel creator({String? email = 'me@example.com'}) =>
      CreatePrivateRoomViewModel(
        roomRepository: rooms,
        authRepository: FakeAuthRepository(email: email),
      );

  group('CreatePrivateRoomViewModel', () {
    test('creates the room', () async {
      final viewModel = creator();

      await viewModel.create.execute((name: ' Family ', password: 'secret'));

      expect(viewModel.create.value!.name, 'Family');
      expect(viewModel.create.value!.id, 'family');
    });

    test('a taken name fails with nameTaken', () async {
      await rooms.createRoom(
          name: 'family', password: 'x', createdBy: 'a@example.com');
      final viewModel = creator();

      await viewModel.create.execute((name: 'Family', password: 'secret'));

      expect(
          viewModel.create.error, _failsWith(PrivateRoomErrorCode.nameTaken));
    });

    test('without a signed-in user creates nothing', () async {
      final viewModel = creator(email: null);

      await viewModel.create.execute((name: 'Family', password: 'secret'));

      expect(viewModel.create.completed, isTrue);
      expect(viewModel.create.value, isNull);
      expect(rooms.joinRoom(name: 'Family', password: 'secret'),
          throwsA(_failsWith(PrivateRoomErrorCode.roomNotFound)));
    });
  });

  group('JoinPrivateRoomViewModel', () {
    setUp(() => rooms.createRoom(
        name: 'Family', password: 'secret', createdBy: 'a@example.com'));

    test('joins with the right password, case-insensitively', () async {
      final viewModel = JoinPrivateRoomViewModel(roomRepository: rooms);

      await viewModel.join.execute((name: 'FAMILY', password: 'secret'));

      expect(viewModel.join.value!.name, 'Family');
    });

    test('a wrong password or unknown room fails', () async {
      final viewModel = JoinPrivateRoomViewModel(roomRepository: rooms);

      await viewModel.join.execute((name: 'Family', password: 'nope'));
      expect(
          viewModel.join.error, _failsWith(PrivateRoomErrorCode.wrongPassword));

      await viewModel.join.execute((name: 'Friends', password: 'secret'));
      expect(
          viewModel.join.error, _failsWith(PrivateRoomErrorCode.roomNotFound));
    });
  });
}
