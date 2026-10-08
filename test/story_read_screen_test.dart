import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/ad_banner.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/models/story.dart';
import 'package:cadavre_exquisite/screens/story_read_screen.dart';
import 'package:cadavre_exquisite/services/ads_service.dart';
import 'package:cadavre_exquisite/services/user_profile_service.dart';

import 'fake_ads_service.dart';

void main() {
  final timestamp = Timestamp.fromMillisecondsSinceEpoch(0);

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

  Widget buildApp(
    UserProfileService service, {
    AdsService? adsService,
    String? title,
  }) =>
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: StoryReadScreen(
          story: buildStory(title: title),
          profileService: service,
          adsService: adsService,
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
      buildApp(UserProfileService(firestore: firestore)),
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
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('userProfiles')
        .doc('mario.rossi@example.com')
        .set({'nickname': 'Supermario'});

    await tester.pumpWidget(
      buildApp(UserProfileService(firestore: firestore)),
    );

    // First frame: no spinner, parts and masked fallbacks already visible.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Once upon a time'), findsOneWidget);
    expect(find.text('— Ma***'), findsOneWidget);
    expect(find.text('— lu***'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('— Supermario'), findsOneWidget);
  });

  testWidgets('has a story-read banner slot that takes no space without an ad',
      (tester) async {
    final ads = FakeAdsService(available: true);
    await tester.pumpWidget(buildApp(
      UserProfileService(firestore: FakeFirebaseFirestore()),
      adsService: ads,
    ));
    await tester.pumpAndSettle();

    final banner = find.byType(AdBanner);
    expect(banner, findsOneWidget);
    expect(
        tester.widget<AdBanner>(banner).placement, AdPlacement.storyReadBanner);
    // Not inside the scrolling story.
    expect(
      find.ancestor(of: banner, matching: find.byType(SingleChildScrollView)),
      findsNothing,
    );
    expect(ads.requested, [AdPlacement.storyReadBanner]);
    expect(tester.getSize(banner), Size.zero);
  });

  testWidgets('shows the AI title above the parts when the story has one',
      (tester) async {
    final service = UserProfileService(firestore: FakeFirebaseFirestore());

    await tester.pumpWidget(buildApp(service, title: 'The Seated Cat'));
    await tester.pumpAndSettle();
    expect(find.text('The Seated Cat'), findsOneWidget);
  });
}
