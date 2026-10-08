import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/ad_banner.dart';
import 'package:cadavre_exquisite/ad_banner_view.dart';
import 'package:cadavre_exquisite/services/ads_service.dart';

import 'fake_ads_service.dart';

void main() {
  Widget host(Widget banner) => MaterialApp(
        home: Scaffold(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [banner],
          ),
        ),
      );

  testWidgets('renders nothing while ads are unavailable', (tester) async {
    final service = FakeAdsService(
      unitIds: {AdPlacement.storyReadBanner: 'ca-app-pub-x/1'},
    );
    await tester.pumpWidget(host(AdBanner(
      placement: AdPlacement.storyReadBanner,
      adsService: service,
    )));

    expect(tester.getSize(find.byType(AdBanner)), Size.zero);
    expect(find.byType(AdBannerView), findsNothing);
    // Unit ids are not even asked for until ads are available.
    expect(service.requested, isEmpty);
  });

  testWidgets('renders nothing when the placement has no unit id',
      (tester) async {
    final service = FakeAdsService(available: true);
    await tester.pumpWidget(host(AdBanner(
      placement: AdPlacement.completeStoriesBanner,
      adsService: service,
    )));

    expect(tester.getSize(find.byType(AdBanner)), Size.zero);
    expect(find.byType(AdBannerView), findsNothing);
    expect(service.requested, [AdPlacement.completeStoriesBanner]);
  });

  testWidgets('re-checks the unit id when ads become available',
      (tester) async {
    // No unit id configured, so no real ad is ever requested.
    final service = FakeAdsService();
    await tester.pumpWidget(host(AdBanner(
      placement: AdPlacement.storyReadBanner,
      adsService: service,
    )));
    expect(service.requested, isEmpty);

    service.available = true;
    await tester.pump();

    expect(service.requested, [AdPlacement.storyReadBanner]);
    expect(tester.getSize(find.byType(AdBanner)), Size.zero);
    expect(find.byType(AdBannerView), findsNothing);
  });

  testWidgets('defaults to the no-op service under flutter test',
      (tester) async {
    await tester.pumpWidget(
      host(const AdBanner(placement: AdPlacement.storyReadBanner)),
    );

    expect(AdsService.instance, isA<NoopAdsService>());
    expect(tester.getSize(find.byType(AdBanner)), Size.zero);
  });
}
