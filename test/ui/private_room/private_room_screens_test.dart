import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/private_room/private_room_repository.dart';
import 'package:cadavre_exquisite/domain/models/private_room.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/private_room/widgets/create_private_room_screen.dart';
import 'package:cadavre_exquisite/ui/private_room/widgets/join_private_room_screen.dart';
import 'package:cadavre_exquisite/ui/private_room/widgets/private_room_screen.dart';

import '../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../testing/fakes/repositories/fake_private_room_repository.dart';

void main() {
  late AppLocalizations l10n;
  late FakePrivateRoomRepository rooms;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() => rooms = FakePrivateRoomRepository());

  /// Opens the private room menu from a page that records what it pops.
  Future<List<PrivateRoom?>> openMenu(WidgetTester tester) async {
    final results = <PrivateRoom?>[];
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthRepository>(
            create: (_) => FakeAuthRepository(email: 'me@example.com')),
        Provider<PrivateRoomRepository>.value(value: rooms),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => results.add(
                await Navigator.push<PrivateRoom>(
                  context,
                  MaterialPageRoute(builder: (_) => const PrivateRoomScreen()),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  Future<void> fill(WidgetTester tester, List<String> values) async {
    final fields = find.byType(TextFormField);
    for (var i = 0; i < values.length; i++) {
      await tester.enterText(fields.at(i), values[i]);
    }
  }

  Future<void> tapSubmit(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('creating a room returns it to the caller', (tester) async {
    final results = await openMenu(tester);
    await tapSubmit(tester, l10n.createRoomButton);
    expect(find.byType(CreatePrivateRoomScreen), findsOneWidget);

    await fill(tester, ['Family', 'secret', 'secret']);
    await tapSubmit(tester, l10n.createRoomButton);

    expect(find.byType(PrivateRoomScreen), findsNothing);
    expect(results.single!.name, 'Family');
  });

  testWidgets('a taken room name shows its message and stays', (tester) async {
    await rooms.createRoom(
        name: 'Family', password: 'x', createdBy: 'a@example.com');
    await openMenu(tester);
    await tapSubmit(tester, l10n.createRoomButton);

    await fill(tester, ['family', 'secret', 'secret']);
    await tapSubmit(tester, l10n.createRoomButton);

    expect(find.text(l10n.errorRoomNameTaken), findsOneWidget);
    expect(find.byType(CreatePrivateRoomScreen), findsOneWidget);
  });

  testWidgets('an invalid form is not submitted', (tester) async {
    await openMenu(tester);
    await tapSubmit(tester, l10n.createRoomButton);

    await fill(tester, ['Family', 'secret', 'other']);
    await tapSubmit(tester, l10n.createRoomButton);

    expect(find.text(l10n.roomPasswordMismatch), findsOneWidget);
    expect(rooms.joinRoom(name: 'Family', password: 'secret'),
        throwsA(isA<PrivateRoomException>()));
  });

  testWidgets(
      'joining returns the room; a wrong password shows the '
      'generic join message', (tester) async {
    await rooms.createRoom(
        name: 'Family', password: 'secret', createdBy: 'a@example.com');
    final results = await openMenu(tester);
    await tapSubmit(tester, l10n.joinRoomButton);
    expect(find.byType(JoinPrivateRoomScreen), findsOneWidget);

    await fill(tester, ['Family', 'wrong']);
    await tapSubmit(tester, l10n.joinRoomButton);
    expect(find.text(l10n.errorRoomJoinFailed), findsOneWidget);
    expect(find.byType(JoinPrivateRoomScreen), findsOneWidget);

    await fill(tester, ['Family', 'secret']);
    await tapSubmit(tester, l10n.joinRoomButton);

    expect(find.byType(PrivateRoomScreen), findsNothing);
    expect(results.single!.id, 'family');
  });
}
