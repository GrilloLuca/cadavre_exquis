import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/ads/ads_repository.dart';
import 'package:cadavre_exquisite/domain/models/ad_placement.dart';
import 'package:cadavre_exquisite/ui/core/ui/ad_banner.dart';
import 'package:cadavre_exquisite/ui/core/ui/ad_banner_view.dart';

import '../../../testing/fakes/repositories/fake_ads_repository.dart';

void main() {
  Widget host(FakeAdsRepository ads, AdPlacement placement) =>
      ChangeNotifierProvider<AdsRepository>.value(
        value: ads,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [AdBanner(placement: placement)],
            ),
          ),
        ),
      );

  testWidgets('renders nothing while ads are unavailable', (tester) async {
    final ads = FakeAdsRepository(
      unitIds: {AdPlacement.storyReadBanner: 'ca-app-pub-x/1'},
    );
    await tester.pumpWidget(host(ads, AdPlacement.storyReadBanner));

    expect(tester.getSize(find.byType(AdBanner)), Size.zero);
    expect(find.byType(AdBannerView), findsNothing);
    // Unit ids are not even asked for until ads are available.
    expect(ads.requested, isEmpty);
  });

  testWidgets('renders nothing when the placement has no unit id',
      (tester) async {
    final ads = FakeAdsRepository(available: true);
    await tester.pumpWidget(host(ads, AdPlacement.completeStoriesBanner));

    expect(tester.getSize(find.byType(AdBanner)), Size.zero);
    expect(find.byType(AdBannerView), findsNothing);
    expect(ads.requested, [AdPlacement.completeStoriesBanner]);
  });

  testWidgets('re-checks the unit id when ads become available',
      (tester) async {
    // No unit id configured, so no real ad is ever requested.
    final ads = FakeAdsRepository();
    await tester.pumpWidget(host(ads, AdPlacement.storyReadBanner));
    expect(ads.requested, isEmpty);

    ads.available = true;
    await tester.pump();

    expect(ads.requested, [AdPlacement.storyReadBanner]);
    expect(tester.getSize(find.byType(AdBanner)), Size.zero);
    expect(find.byType(AdBannerView), findsNothing);
  });
}
