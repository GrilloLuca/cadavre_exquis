import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/ui/story_read/widgets/story_read_screen.dart';

import '../../../testing/fakes/repositories/fake_user_profile_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository_firestore.dart';

/// Answers nickname lookups only once [_gate] completes.
class _GatedProfileRepository extends FakeUserProfileRepository {
  _GatedProfileRepository(this._gate, {super.nicknames});

  final Future<void> _gate;

  @override
  Future<Map<String, String>> nicknamesFor(Iterable<String> emails) async {
    await _gate;
    return super.nicknamesFor(emails);
  }
}

/// Counts nickname lookups.
class _CountingProfileRepository extends FakeUserProfileRepository {
  _CountingProfileRepository({super.nicknames});

  int lookups = 0;

  @override
  Future<Map<String, String>> nicknamesFor(Iterable<String> emails) {
    lookups++;
    return super.nicknamesFor(emails);
  }
}

void main() {
  final timestamp = DateTime.fromMillisecondsSinceEpoch(0);

  Story buildStory({String? title}) => Story(
        id: 'story-1',
        title: title,
        status: 'complete',
        currentPosition: 'epilogo',
        parts: [
          StoryPart(
            position: 'introduzione',
            text: 'Once upon a time',
            author: 'Mario.Rossi@example.com',
            timestamp: timestamp,
          ),
          StoryPart(
            position: 'sviluppo1',
            text: 'a cat sat down',
            author: 'luca.grillo@gmail.com',
            timestamp: timestamp,
          ),
        ],
      );

  Widget buildApp(UserProfileRepository service, {String? title}) =>
      Provider<UserProfileRepository>.value(
        value: service,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: StoryReadScreen(story: buildStory(title: title)),
        ),
      );

  testWidgets('shows nicknames, falls back to masked emails, never the email',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('userProfiles')
        .doc('mario.rossi@example.com')
        .set({'nickname': 'Supermario'});

    await tester.pumpWidget(
      buildApp(UserProfileRepositoryFirestore(firestore: firestore)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Once upon a time'), findsOneWidget);
    expect(find.text('a cat sat down'), findsOneWidget);
    expect(find.text('— Supermario'), findsOneWidget);
    expect(find.text('— lu***'), findsOneWidget);

    expect(find.textContaining('@'), findsNothing);
    expect(find.textContaining('gmail'), findsNothing);
    expect(find.textContaining('example.com'), findsNothing);
    expect(find.textContaining('luca.grillo'), findsNothing);
  });

  testWidgets('renders parts with masked authors before nicknames load',
      (tester) async {
    final lookup = Completer<void>();
    final service = _GatedProfileRepository(
      lookup.future,
      nicknames: {'mario.rossi@example.com': 'Supermario'},
    );

    await tester.pumpWidget(buildApp(service));

    // Nicknames still loading: no spinner, parts and masked fallbacks
    // already visible.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Once upon a time'), findsOneWidget);
    expect(find.text('— Ma***'), findsOneWidget);
    expect(find.text('— lu***'), findsOneWidget);

    lookup.complete();
    await tester.pumpAndSettle();
    expect(find.text('— Supermario'), findsOneWidget);
  });

  testWidgets('shows the AI title above the parts when the story has one',
      (tester) async {
    final service =
        UserProfileRepositoryFirestore(firestore: FakeFirebaseFirestore());

    await tester.pumpWidget(buildApp(service, title: 'The Seated Cat'));
    await tester.pumpAndSettle();
    expect(find.text('The Seated Cat'), findsOneWidget);
  });

  testWidgets('an app rebuild does not reload the nicknames', (tester) async {
    // The route's builder runs again when the Navigator's dependencies
    // change. A ViewModel created there flipped the authors back to masked
    // emails and reloaded the nicknames each time.
    final service = _CountingProfileRepository(
        nicknames: {'mario.rossi@example.com': 'Supermario'});
    late StateSetter rebuildApp;
    await tester.pumpWidget(Provider<UserProfileRepository>.value(
      value: service,
      child: StatefulBuilder(builder: (context, setState) {
        rebuildApp = setState;
        return MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StoryReadScreen(story: buildStory()),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('— Supermario'), findsOneWidget);

    rebuildApp(() {});
    await tester.pump();

    expect(find.text('— Supermario'), findsOneWidget);
    expect(find.text('— Ma***'), findsNothing);
    expect(service.lookups, 1);
  });
}
