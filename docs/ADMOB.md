# AdMob — status and remaining work

Tracking doc for monetizing the app with Google AdMob. Branch: `feature/admob`
(commits `0ac2868` cleanup, `20c15f1` AdMob). Update this file as tasks close.

## What is done

- `google_mobile_ads` 9.1.0, native config with Google's **test** App IDs
  (`android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`),
  SKAdNetworkItems, `NSUserTrackingUsageDescription` (English only).
- Service layer in `lib/services/`:
  - `ads_service.dart`: `AdsService` (abstract, `AdsService.instance`,
    overridable in tests), `NoopAdsService` (web, desktop, `flutter test`).
  - `google_ads_service.dart`: UMP consent → `MobileAds.initialize()` only if
    `canRequestAds()`. `adsAvailable` and `privacyOptionsRequired` are
    `ValueListenable<bool>`.
  - `ads_config.dart`: debug/profile → Google test ad units; release → only
    `--dart-define` values, fail-closed (missing/invalid/test id ⇒ no ads).
  - `ads_service_factory*.dart`: conditional import keeps the plugin out of web.
- Init after the first frame in `HomeScreen.initState`.
- `lib/ad_banner.dart` (+ `ad_banner_view.dart`, `ad_banner_view_web.dart`):
  large anchored adaptive banner.
- Placements: completed-stories tab (built only when `_selectedIndex == 1`,
  outside the `IndexedStack`) and bottom of `StoryReadScreen`. No ads
  anywhere else — never in `ChatScreen`, login, account or room screens.
- `AccountScreen`: "Privacy e annunci" entry (shown when
  `privacyOptionsRequired` is true) reopening the UMP privacy form.

### Release defines

| Define | Use |
|---|---|
| `ADMOB_BANNER_COMPLETE_STORIES_ANDROID` / `_IOS` | Completed-stories tab banner |
| `ADMOB_BANNER_STORY_READ_ANDROID` / `_IOS` | Story reader banner |
| `ADMOB_INTERSTITIAL_ANDROID` / `_IOS` | Not used yet (see QA finding 6) |
| `ADMOB_DEBUG_EEA=true` | Debug only: simulate EEA consent flow |
| `ADMOB_TEST_DEVICE_IDS=a,b` | Debug only: physical test devices for UMP |

Manual test of consent: `flutter run --dart-define=ADMOB_DEBUG_EEA=true`.

## Remaining work before release

### Owner tasks (consoles and stores)

- [ ] **AdMob account**: create the account, two apps (Android
  `com.lucagrillo.cadavreexquis`, iOS), ad units (2 banners per platform),
  register test devices, set payment/tax details.
- [ ] **AdMob Privacy & messaging**: GDPR message (it/en) with privacy policy
  URL; IDFA explainer message if ATT is kept (see decision 4).
- [ ] **Privacy policy**: update to mention AdMob and link it from the app.
- [ ] **app-ads.txt** on the developer website declared in both stores
  (`google.com, pub-XXXXXXXXXXXXXXXX, DIRECT, f08c47fec0942fa0`). No site yet —
  Firebase Hosting is an option (`firebase.json` has no hosting today).
- [ ] **App Store Connect privacy labels** and **Play Console**: "Contains ads",
  Advertising ID declaration, Data safety (device IDs, interactions,
  diagnostics, approximate location, shared for advertising).
- [ ] Link both apps to the stores in AdMob and pass AdMob app review.

### Code tasks

- [ ] **Real App IDs** (QA finding 2): replace the test App IDs in
  `AndroidManifest.xml` and `Info.plist`. Release builds must not ship the
  test App ID: either inject per build (`manifestPlaceholders` in
  `android/app/build.gradle`, `$(ADMOB_APP_ID)` xcconfig on iOS) or keep the
  real id in the repo and fail the release build if the test id
  (`ca-app-pub-3940256099942544~…`) is still there.
- [ ] **CI/fastlane** (T8): new secret `ADMOB_CONFIG_JSON` written to a
  gitignored `ads.json` in `.github/workflows/deploy.yml`; pass
  `--dart-define-from-file=ads.json` in `android/fastlane/Fastfile` and
  `ios/fastlane/Fastfile` build lanes; fail clearly if missing; document the
  secret in `docs/CI_CD.md`. `release.yml` promotes the beta binary without
  rebuilding, so production ids must already be in the beta build.
- [ ] **`ios/fastlane/Fastfile`**: `add_id_info_uses_idfa: false` is no longer
  true with AdMob — revisit.
- [ ] **AdBanner tests** (QA finding 4): mock the
  `plugins.flutter.io/google_mobile_ads` MethodChannel to cover dispose
  during load, reload on width change, failed load, keyboard open.
- [ ] **Keyboard branch** (QA finding 5): `ad_banner_view.dart` only hides the
  `AdWidget` with the keyboard open while the `BannerAd` keeps refreshing.
  Neither banner screen has a text field, so drop the branch, or dispose the
  ad while hidden.
- [ ] **Interstitial plumbing** (QA finding 6): unused; `hasAnyAdUnit` counts
  it, so a release with only interstitial ids would show consent with no ad.
  Remove until there is a caller. Also drop the unreachable `kIsWeb` check in
  `ads_service_factory.dart`.
- [ ] **Age TODOs** in `google_ads_service.dart` (`tagForUnderAgeOfConsent`,
  `ageRestrictedTreatment`) once decision 1 is made.
- [ ] **Manual check on device** with test ids: banner load, rotation, layout
  above the nav bar, bottom inset on `StoryReadScreen` on iPhone (background
  image may show under the banner near the home indicator).
- [ ] **Version**: bump minor for the first release with ads
  (`cd android && bundle exec fastlane android bump type:minor`).
- [ ] **Rollout**: ship with ads off, then enable gradually (Remote Config
  `ads_enabled` flag is planned, not implemented) and watch crashes, reviews,
  fill rate and policy warnings for a week.

### Later / optional

- [ ] Firebase Remote Config flags (`ads_enabled`, per-placement switches,
  interstitial caps).
- [ ] Interstitial after leaving `StoryReadScreen`, frequency-capped (max 1
  every 3 min, every 3rd event, 6/day, not in the first 2 sessions).
- [ ] "Remove ads" in-app purchase (`in_app_purchase`, server-validated flag on
  `users/{uid}`, `NoopAdsService` for buyers).

## Open decisions (owner)

1. **Store audience/age**: 13+, 16+ or 18+? Drives the age tags and whether
   the Families Program applies.
2. **Home banner position** (QA finding 3): it sits directly above the
   BottomNavigationBar (1dp divider + 8dp), which AdMob flags as an
   accidental-click risk. Increase the separation, or move it to the top of
   the completed-stories list (still outside the `IndexedStack`).
3. **Interstitials**: none for now, only after reading a story, or also after
   writing the epilogue?
4. **iOS tracking (ATT)**: ask for tracking (more revenue, one more prompt) →
   enable the IDFA message in AdMob and localize the text in it/en
   `InfoPlist.strings` (needs Xcode to add the variant group); or no tracking
   → remove `NSUserTrackingUsageDescription`.
5. **Domain** for `app-ads.txt` and the privacy policy.
6. **"Remove ads" purchase**: yes/no, when.
