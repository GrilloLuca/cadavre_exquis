import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/screens/account_screen.dart';
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

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(saveButton(), warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  testWidgets('prefills the saved nickname and previews it', (tester) async {
    await seedNickname('Supermario');
    await pumpScreen(tester);

    expect(fieldText(tester), 'Supermario');
    expect(
        find.text('Nelle storie apparirai come: Supermario'), findsOneWidget);
    expect(
      find.text('2–20 caratteri: lettere, numeri, spazi, _ - .'),
      findsOneWidget,
    );
    expect(isSaveEnabled(tester), isTrue);
    expect(find.text('Impossibile caricare il nickname.'), findsNothing);
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

    expect(find.text('Nickname salvato.'), findsOneWidget);
    expect(storedProfiles()[_docId]?['nickname'], 'Luca Grillo');
    expect(fieldText(tester), 'Luca Grillo');
  });

  testWidgets('clearing and saving deletes the profile', (tester) async {
    await seedNickname('Supermario');
    await pumpScreen(tester);

    await tester.enterText(field(), '');
    await tapSave(tester);

    expect(find.text('Nickname rimosso.'), findsOneWidget);
    expect(storedProfiles(), isEmpty);
  });

  for (final (input, message) in [
    ('a', 'Il nickname deve avere almeno 2 caratteri.'),
    ('luca@x', 'Usa solo lettere, numeri, spazi e _ - .'),
  ]) {
    testWidgets('invalid "$input" shows the error and writes nothing',
        (tester) async {
      await seedNickname('Supermario');
      await pumpScreen(tester);

      await tester.enterText(field(), input);
      await tester.pump();

      expect(find.text(message), findsOneWidget);
      // The preview never shows an invalid nickname.
      expect(find.text('Nelle storie apparirai come: Lu***'), findsOneWidget);

      await tapSave(tester);

      expect(find.text('Nickname salvato.'), findsNothing);
      expect(storedProfiles()[_docId]?['nickname'], 'Supermario');
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

    await tapSave(tester);
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
    await tapSave(tester);

    expect(find.text('Si è verificato un errore. Riprova.'), findsOneWidget);
    expect(find.text('Nickname salvato.'), findsNothing);
    expect(isSaveEnabled(tester), isTrue);
  });

  testWidgets('a load failure disables the form and never deletes',
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

    expect(find.text('Nickname rimosso.'), findsNothing);
    expect(storedProfiles()[_docId]?['nickname'], 'Supermario');
  });

  testWidgets('retrying after a load failure prefills and re-enables',
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
    expect(isSaveEnabled(tester), isTrue);
    expect(isFieldEnabled(tester), isTrue);

    await tester.enterText(field(), 'Luca');
    await tapSave(tester);
    expect(find.text('Nickname salvato.'), findsOneWidget);
    expect(storedProfiles()[_docId]?['nickname'], 'Luca');
  });
}
