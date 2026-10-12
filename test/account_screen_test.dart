import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/models/private_room.dart';
import 'package:cadavre_exquisite/models/story_language.dart';
import 'package:cadavre_exquisite/screens/account_screen.dart';
import 'package:cadavre_exquisite/services/language_room_preference.dart';
import 'package:cadavre_exquisite/services/user_profile_service.dart';

const _email = 'Luca.Grillo@Gmail.com';
const _docId = 'luca.grillo@gmail.com';

/// A [UserProfileService] whose [getNickname] fails while [failLoads] is
/// set, so a test can recover from a load failure (mock_exceptions has no
/// public way to unregister a throw).
class _FlakyProfileService extends UserProfileService {
  _FlakyProfileService({required super.firestore});

  bool failLoads = true;

  @override
  Future<String?> getNickname(String email) async {
    if (failLoads) throw FirebaseException(plugin: 'cloud_firestore');
    return super.getNickname(email);
  }
}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  DocumentReference<Map<String, dynamic>> profileRef() =>
      firestore.collection('userProfiles').doc(_docId);

  Future<void> seedNickname(String nickname) =>
      profileRef().set({'nickname': nickname});

  /// The non-empty stored profiles, read from the fake's raw dump so this keeps
  /// working when `get` on the profile document is made to throw.
  Map<String, dynamic> storedProfiles() {
    final dump = jsonDecode(firestore.dump()) as Map<String, dynamic>;
    final profiles = (dump['userProfiles'] as Map<String, dynamic>?) ?? {};
    // The fake keeps empty nodes for documents that were read or deleted.
    return {
      for (final MapEntry(:key, :value) in profiles.entries)
        if (value is Map && value.isNotEmpty) key: value,
    };
  }

  Widget buildApp(UserProfileService service) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('it'),
        home: AccountScreen(profileService: service, email: _email),
      );

  Future<void> pumpScreen(WidgetTester tester,
      [UserProfileService? service]) async {
    await tester.pumpWidget(
      buildApp(service ?? UserProfileService(firestore: firestore)),
    );
    await tester.pumpAndSettle();
  }

  Finder field() => find.byType(TextFormField);
  Finder saveButton() => find.widgetWithText(ElevatedButton, 'Salva');
  Finder retryButton() => find.widgetWithText(TextButton, 'Riprova');

  bool isSaveEnabled(WidgetTester tester) =>
      tester.widget<ElevatedButton>(saveButton()).onPressed != null;
  bool isFieldEnabled(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).enabled ?? true;
  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  Finder confirmButton() => find.widgetWithText(TextButton, 'Conferma');
  Finder lockedNote() => find.text('Il nickname non può essere modificato.');

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(saveButton(), warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  /// Taps Save and confirms the one-time choice in the dialog.
  Future<void> saveAndConfirm(WidgetTester tester) async {
    await tapSave(tester);
    await tester.tap(confirmButton());
    await tester.pumpAndSettle();
  }

  testWidgets('a saved nickname is shown read-only, with no save button',
      (tester) async {
    await seedNickname('Supermario');
    await pumpScreen(tester);

    expect(fieldText(tester), 'Supermario');
    expect(
        find.text('Nelle storie apparirai come: Supermario'), findsOneWidget);
    expect(lockedNote(), findsOneWidget);
    expect(isFieldEnabled(tester), isFalse);
    expect(saveButton(), findsNothing);
    expect(find.text('Impossibile caricare il nickname.'), findsNothing);
  });

  testWidgets('without a nickname the field says it can be chosen once',
      (tester) async {
    await pumpScreen(tester);

    expect(
      find.text('2–20 caratteri: lettere, numeri, spazi, _ - .\n'
          'Puoi sceglierlo una sola volta.'),
      findsOneWidget,
    );
    expect(isFieldEnabled(tester), isTrue);
    expect(isSaveEnabled(tester), isTrue);
    expect(lockedNote(), findsNothing);
  });

  testWidgets('without a nickname previews the masked email', (tester) async {
    await pumpScreen(tester);

    expect(fieldText(tester), isEmpty);
    expect(find.text('Nelle storie apparirai come: Lu***'), findsOneWidget);
  });

  testWidgets('saving a valid nickname writes it and confirms', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(field(), '  Luca   Grillo ');
    await tapSave(tester);
    expect(
      find.text('Nelle storie apparirai come «Luca Grillo». '
          'Non potrai più cambiarlo.'),
      findsOneWidget,
    );
    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(find.text('Nickname salvato.'), findsOneWidget);
    expect(storedProfiles()[_docId]?['nickname'], 'Luca Grillo');
    expect(fieldText(tester), 'Luca Grillo');
    // Chosen once: now read-only.
    expect(lockedNote(), findsOneWidget);
    expect(isFieldEnabled(tester), isFalse);
    expect(saveButton(), findsNothing);
  });

  testWidgets('cancelling the confirmation writes nothing', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(field(), 'Luca');
    await tapSave(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Annulla'));
    await tester.pumpAndSettle();

    expect(storedProfiles(), isEmpty);
    expect(find.text('Nickname salvato.'), findsNothing);
    expect(isFieldEnabled(tester), isTrue);
    expect(isSaveEnabled(tester), isTrue);
  });

  testWidgets('saving an empty field does nothing', (tester) async {
    await pumpScreen(tester);

    await tapSave(tester);

    expect(confirmButton(), findsNothing);
    expect(storedProfiles(), isEmpty);
  });

  testWidgets(
      'a nickname set meanwhile elsewhere is reported and shown read-only',
      (tester) async {
    await pumpScreen(tester);
    await seedNickname('Supermario');

    await tester.enterText(field(), 'Luca');
    await saveAndConfirm(tester);

    expect(
      find.text('Hai già scelto un nickname e non può essere cambiato.'),
      findsOneWidget,
    );
    expect(storedProfiles()[_docId]?['nickname'], 'Supermario');
    expect(fieldText(tester), 'Supermario');
    expect(lockedNote(), findsOneWidget);
  });

  for (final (input, message) in [
    ('a', 'Il nickname deve avere almeno 2 caratteri.'),
    ('luca@x', 'Usa solo lettere, numeri, spazi e _ - .'),
  ]) {
    testWidgets('invalid "$input" shows the error and writes nothing',
        (tester) async {
      await pumpScreen(tester);

      await tester.enterText(field(), input);
      await tester.pump();

      expect(find.text(message), findsOneWidget);
      // The preview never shows an invalid nickname.
      expect(find.text('Nelle storie apparirai come: Lu***'), findsOneWidget);

      await tapSave(tester);

      expect(confirmButton(), findsNothing);
      expect(storedProfiles(), isEmpty);
    });
  }

  testWidgets('over-long input is not truncated and is reported',
      (tester) async {
    await pumpScreen(tester);

    final tooLong = 'a' * 25;
    await tester.enterText(field(), tooLong);
    await tester.pump();

    expect(fieldText(tester), tooLong);
    expect(
      find.text('Il nickname può avere al massimo 20 caratteri.'),
      findsOneWidget,
    );

    await tapSave(tester);
    expect(storedProfiles(), isEmpty);
  });

  testWidgets('long raw input that normalizes within the limit is saved',
      (tester) async {
    await pumpScreen(tester);

    // 24 raw characters, 20 once internal whitespace is collapsed.
    await tester.enterText(field(), 'abcdefghi     jklmnopqrs');
    await tester.pump();
    expect(
      find.text('Il nickname può avere al massimo 20 caratteri.'),
      findsNothing,
    );

    await saveAndConfirm(tester);
    expect(
      storedProfiles()[_docId]?['nickname'],
      'abcdefghi jklmnopqrs',
    );
  });

  testWidgets('a Firestore failure on save shows the generic error',
      (tester) async {
    await pumpScreen(tester);
    whenCalling(Invocation.method(#set, null))
        .on(profileRef())
        .thenThrow(FirebaseException(plugin: 'cloud_firestore'));

    await tester.enterText(field(), 'Luca');
    await saveAndConfirm(tester);

    expect(find.text('Si è verificato un errore. Riprova.'), findsOneWidget);
    expect(find.text('Nickname salvato.'), findsNothing);
    expect(isSaveEnabled(tester), isTrue);
  });

  testWidgets('a load failure disables the form and never writes',
      (tester) async {
    await seedNickname('Supermario');
    whenCalling(Invocation.method(#get, null))
        .on(profileRef())
        .thenThrow(FirebaseException(plugin: 'cloud_firestore'));

    await pumpScreen(tester);

    expect(find.text('Impossibile caricare il nickname.'), findsOneWidget);
    expect(retryButton(), findsOneWidget);
    expect(isSaveEnabled(tester), isFalse);
    expect(isFieldEnabled(tester), isFalse);

    // Neither the (disabled) button nor a keyboard "done" may save.
    await tapSave(tester);
    tester
        .widget<TextField>(find.byType(TextField))
        .onSubmitted!(fieldText(tester));
    await tester.pumpAndSettle();

    expect(confirmButton(), findsNothing);
    expect(storedProfiles()[_docId]?['nickname'], 'Supermario');
  });

  testWidgets('retrying after a load failure prefills the saved nickname',
      (tester) async {
    await seedNickname('Supermario');
    final service = _FlakyProfileService(firestore: firestore);
    await pumpScreen(tester, service);

    expect(find.text('Impossibile caricare il nickname.'), findsOneWidget);
    expect(isSaveEnabled(tester), isFalse);

    // A retry that fails again keeps the form disabled.
    await tester.tap(retryButton());
    await tester.pumpAndSettle();
    expect(find.text('Impossibile caricare il nickname.'), findsOneWidget);
    expect(isSaveEnabled(tester), isFalse);

    service.failLoads = false;
    await tester.tap(retryButton());
    await tester.pumpAndSettle();

    expect(find.text('Impossibile caricare il nickname.'), findsNothing);
    expect(retryButton(), findsNothing);
    expect(fieldText(tester), 'Supermario');
    // Already chosen, so it stays read-only.
    expect(lockedNote(), findsOneWidget);
    expect(isFieldEnabled(tester), isFalse);
    expect(saveButton(), findsNothing);
  });

  testWidgets('retrying after a load failure with no nickname enables saving',
      (tester) async {
    final service = _FlakyProfileService(firestore: firestore);
    await pumpScreen(tester, service);
    expect(isSaveEnabled(tester), isFalse);

    service.failLoads = false;
    await tester.tap(retryButton());
    await tester.pumpAndSettle();

    expect(isFieldEnabled(tester), isTrue);
    await tester.enterText(field(), 'Luca');
    await saveAndConfirm(tester);
    expect(find.text('Nickname salvato.'), findsOneWidget);
    expect(storedProfiles()[_docId]?['nickname'], 'Luca');
  });

  group('Room card', () {
    const room = PrivateRoom(id: 'gli amici', name: 'Gli Amici');

    /// Pumps the screen inside a host that owns the room state the way the
    /// home screen does: picking a language also leaves the private room.
    Future<void> pumpRoomCard(
      WidgetTester tester, {
      String? email,
      String languageCode = 'it',
      RoomLanguageSource languageSource = RoomLanguageSource.explicit,
      PrivateRoom? privateRoom,
      List<String>? languageCalls,
      List<PrivateRoom?>? privateRoomCalls,
    }) async {
      var currentLanguage = languageCode;
      var currentSource = languageSource;
      var currentRoom = privateRoom;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('it'),
        home: StatefulBuilder(
          builder: (context, setState) => AccountScreen(
            profileService: UserProfileService(firestore: firestore),
            email: email,
            currentEmail: () => null,
            languageCode: currentLanguage,
            languageSource: currentSource,
            privateRoom: currentRoom,
            onLanguageChanged: (code) {
              languageCalls?.add(code);
              setState(() {
                currentLanguage = code;
                currentSource = RoomLanguageSource.explicit;
                currentRoom = null;
              });
            },
            onPrivateRoomChanged: (value) {
              privateRoomCalls?.add(value);
              setState(() => currentRoom = value);
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Finder languageRow(String nativeName) =>
        find.widgetWithText(ListTile, nativeName);
    Finder notice() => find.text(
        'Sei nella stanza privata “Gli Amici”. La stanza della lingua è in '
        'pausa finché non esci.');
    Finder leaveButton() => find.text('Esci dalla stanza privata');
    Finder trailingOf(String nativeName, IconData icon) => find.descendant(
        of: languageRow(nativeName), matching: find.byIcon(icon));

    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('renders without an email or profile', (tester) async {
      await pumpRoomCard(tester);

      expect(find.text('Stanza'), findsOneWidget);
      expect(find.text('Stanza della lingua'), findsOneWidget);
      for (final language in kStoryLanguages) {
        expect(languageRow(language.nativeName), findsOneWidget);
      }
      expect(find.text('Stanza privata'), findsOneWidget);
      expect(field(), findsNothing);
      expect(find.text('Elimina account'), findsNothing);
    });

    testWidgets('is shown below the nickname card when signed in',
        (tester) async {
      await pumpRoomCard(tester, email: _email);

      expect(field(), findsOneWidget);
      expect(find.text('Stanza'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Stanza')).dy,
        greaterThan(tester.getTopLeft(saveButton()).dy),
      );
    });

    testWidgets('marks exactly the current language as selected',
        (tester) async {
      await pumpRoomCard(tester, languageCode: 'es');

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(trailingOf('Español', Icons.check_circle), findsOneWidget);
      expect(
        tester.getSemantics(languageRow('Español')),
        isSemantics(
          label: 'Español',
          isButton: true,
          hasCheckedState: true,
          isChecked: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(languageRow('English')),
        isSemantics(
          label: 'English',
          isButton: true,
          hasCheckedState: true,
          isChecked: false,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('selecting a language invokes the callback', (tester) async {
      final calls = <String>[];
      await pumpRoomCard(
        tester,
        languageSource: RoomLanguageSource.detected,
        languageCalls: calls,
      );
      expect(find.text('Scelta in base alla lingua del dispositivo.'),
          findsOneWidget);

      await tapVisible(tester, languageRow('Français'));

      expect(calls, ['fr']);
      expect(trailingOf('Français', Icons.check_circle), findsOneWidget);
      // An explicit choice ends auto mode, so the caption goes away.
      expect(find.text('Scelta in base alla lingua del dispositivo.'),
          findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('tapping the auto-detected language stores it explicitly',
        (tester) async {
      final calls = <String>[];
      await pumpRoomCard(
        tester,
        languageSource: RoomLanguageSource.detected,
        languageCalls: calls,
      );

      await tapVisible(tester, languageRow('Italiano'));

      expect(calls, ['it']);
      expect(find.text('Scelta in base alla lingua del dispositivo.'),
          findsNothing);
    });

    testWidgets('explains the English fallback', (tester) async {
      await pumpRoomCard(
        tester,
        languageCode: 'en',
        languageSource: RoomLanguageSource.fallback,
      );

      expect(
        find.text('Non c\'è ancora una stanza nella lingua del dispositivo, '
            'quindi sei in quella inglese.'),
        findsOneWidget,
      );
      expect(find.text('Scelta in base alla lingua del dispositivo.'),
          findsNothing);
    });

    testWidgets('an explicit choice shows no caption', (tester) async {
      await pumpRoomCard(tester);

      expect(find.byIcon(Icons.smartphone), findsNothing);
    });

    testWidgets('shows the private room with its notice and Leave',
        (tester) async {
      await pumpRoomCard(tester, languageCode: 'de', privateRoom: room);

      expect(notice(), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Gli Amici'), findsOneWidget);
      expect(leaveButton(), findsOneWidget);
      expect(
          find.text('Gioca solo con gli amici che ne conoscono nome e '
              'password.'),
          findsNothing);
      // The language rows show the room the user goes back to, without the
      // "you are here" fill and check.
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(trailingOf('Deutsch', Icons.check), findsOneWidget);
      expect(
        tester.widget<ListTile>(languageRow('Deutsch')).tileColor,
        isNull,
      );
    });

    testWidgets('Leave clears the private room and Undo restores it',
        (tester) async {
      final calls = <PrivateRoom?>[];
      await pumpRoomCard(tester, privateRoom: room, privateRoomCalls: calls);

      await tapVisible(tester, leaveButton());

      expect(calls, [null]);
      expect(notice(), findsNothing);
      expect(leaveButton(), findsNothing);
      expect(find.text('Hai lasciato “Gli Amici”.'), findsOneWidget);
      expect(trailingOf('Italiano', Icons.check_circle), findsOneWidget);

      await tester.tap(find.widgetWithText(SnackBarAction, 'Annulla'));
      await tester.pumpAndSettle();

      expect(calls, [null, same(room)]);
      expect(notice(), findsOneWidget);
    });

    testWidgets('tapping a language in a private room leaves it',
        (tester) async {
      final languageCalls = <String>[];
      final roomCalls = <PrivateRoom?>[];
      await pumpRoomCard(
        tester,
        privateRoom: room,
        languageCalls: languageCalls,
        privateRoomCalls: roomCalls,
      );

      await tapVisible(tester, languageRow('Español'));

      expect(languageCalls, ['es']);
      expect(notice(), findsNothing);
      expect(leaveButton(), findsNothing);
      expect(trailingOf('Español', Icons.check_circle), findsOneWidget);
      expect(find.text('Hai lasciato “Gli Amici”.'), findsOneWidget);

      // Undo goes back into the room; the new language is kept for later.
      await tester.tap(find.widgetWithText(SnackBarAction, 'Annulla'));
      await tester.pumpAndSettle();

      expect(roomCalls, [same(room)]);
      expect(notice(), findsOneWidget);
      expect(trailingOf('Español', Icons.check), findsOneWidget);
    });

    testWidgets('fits a 320dp screen at 2x text', (tester) async {
      tester.view.physicalSize = const Size(320.0, 640.0);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpRoomCard(
        tester,
        email: _email,
        languageSource: RoomLanguageSource.fallback,
        privateRoom: const PrivateRoom(
          id: 'una stanza dal nome davvero molto lungo',
          name: 'Una stanza dal nome davvero molto lungo',
        ),
      );
      await tester.ensureVisible(leaveButton());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(leaveButton(), findsOneWidget);
    });
  });
}
