# Age signals as first source for the mature-stories gate

Status: proposed (2026-10-09), branch `feature/mature-stories`.

## Goal
On tap of "Storie per adulti", ask the platform first (Play Age Signals on Android, Declared Age Range on iOS 26+). Fall back to the existing neutral birth-year screen only when no signal is available. Firestore rules and Cloud Functions stay as they are.

## Plugin facts (`age_range_signals` 0.10.1, checked in pub cache)
- Flow: `initialize(ageGates: [18])`, then `requestAgeSignalsAccess()` returns `shared | notShared | verificationRequired | unknown`. Only after `shared` do you call `checkAgeSignals()`, which returns `AgeSignalsResult{status, ageLower, ageUpper, ageRangeSource (Android), source (iOS)}`.
- `AgeSignalsStatus`: `verified` (range starts at or above the highest gate), `supervised` (below the gate; this is an age verdict), `supervisedApprovalPending` and `supervisedApprovalDenied` (Android), `declined` (iOS), `unknown`.
- Parent-managed Android accounts: `ageRangeSource == tierB`.
- Exceptions (all `AgeSignalsException`): `UnsupportedPlatform` (iOS < 26, built with an old Xcode), `ApiNotAvailable`, `MissingEntitlement`, `UserCancelled`, `Network`, `PlayServices`, `ApiError`, and others.
- **UI:** on iOS, `checkAgeSignals()` shows Apple's sharing sheet. On Android, `requestAgeSignalsAccess()` may show a Play sheet. So the check only runs on an explicit tap, never in `initState`.
- **Minimum versions:** Android minSdk 23 (ours is `flutter.minSdkVersion`, 24 or higher). The iOS target is 13 (ours is 15.0). SwiftPM is supported (the project uses SwiftPM, with no Podfile). AGP 8.11 and Kotlin 2.2.20 are fine. No minSdk, platform or Info.plist changes are needed.
- **Android availability:** Play answers only for installs from Play (or license testers), in covered regions. Everywhere else we fall back.
- **Mocks:** Android supports `useMockData` in debug builds only. iOS has no mock: testing needs a real device on 26.2+ with a sandbox account.

## Decision: persistence (ADR-lite)
**Don't persist signal results to Firestore. Cache definitive results (adult or minor) in memory for the app session.**
- Signals change over time (birthdays, parental changes). A write-once doc would freeze a stale value, and the rules only accept `birthYear:int`. Writing a derived year would fake precision and loosen the meaning of the doc.
- Not storing the data keeps the Play Data safety and Apple privacy story simple: age data never leaves the device.
- The session cache avoids showing the system sheet again on every tap. "Unavailable" is never cached, so later taps retry.
- Trade-off: one signal request per session per user (a sheet may appear once per launch). This is acceptable for a rarely used section.

**Conflicts: any minor verdict wins.** A stored birth year that says minor denies access without calling the plugin. A stored adult year is still checked against the signal, and a signal that says minor overrides it. A signal of 18+ never overrides a stored minor year. The year comparison ages people out naturally, so this can't lock anyone out for good.

## Design
- `abstract class AgeSignalsSource { Future<AgeSignal> check(); }`, with `enum AgeSignal { adult, minor, unavailable }`.
- `PluginAgeSignalsSource implements AgeSignalsSource`. It maps plugin output through a pure static function `mapSignal(AgeSignalsAccessStatus, AgeSignalsResult?)`, so the mapping can be tested without the plugin. It catches every exception and returns `unavailable`. It returns `unavailable` straight away on platforms other than Android or iOS.
- `AgeGate` service with `AgeGate({AgeSignalsSource? signals, AgeCheckService? storage, Duration timeout, DateTime Function()? clock})` and two methods:
  - `Future<int?> storedBirthYear(email)` is passive, has no UI, and lets the tile hide itself for known minors.
  - `Future<AgeVerdict> resolve(email)` returns `adult`, `minor` or `askBirthYear`.

### Signal mapping
| Plugin output | AgeSignal |
|---|---|
| access is not `shared` | unavailable |
| `verified` and `ageLower >= 18` and not `tierB` | adult |
| `supervised`, `supervisedApprovalPending`, `supervisedApprovalDenied`, `tierB`, or `ageLower < 18` | minor |
| `declined`, `unknown`, null result, any exception, timeout | unavailable |

### `resolve` decision table
| Stored birth year | Signal | Verdict |
|---|---|---|
| minor | (not called) | minor |
| adult | adult or unavailable | adult |
| adult | minor | minor |
| none | adult | adult (nothing written) |
| none | minor | minor (nothing written) |
| none | unavailable | askBirthYear, then the existing flow (write once) |

- **Timeout:** wrap the whole signal call in `.timeout(20s)` (configurable), which yields `unavailable`. 20s leaves room for a system sheet without letting a silent hang block the user. The tile spinner shows while the check runs, and double taps stay blocked.
- **Session cache:** a static map from email to `AgeSignal`, for adult and minor only.

## Tasks

### B1 (backend-developer): signal source, mapping and gate service (about 5h)
- Add `age_range_signals: ^0.10.1`. Create `lib/services/age_signals_source.dart` and `lib/services/age_gate.dart`. `AgeCheckService` is unchanged.
- Add `test/age_signals_mapping_test.dart` and `test/age_gate_test.dart`, using a fake source and `FakeFirebaseFirestore` with a fixed clock.
- **Acceptance criteria:**
  - Every row of both tables has a test.
  - Timeout and exceptions resolve to `askBirthYear`, or to `adult` when the stored year is adult.
  - A stored minor never calls the source (verified with a call counter on the fake).
  - Only adult and minor results are cached.
  - Nothing ever writes to Firestore from a signal.
  - `flutter analyze` is clean and `flutter test` passes.

### F1 (frontend-developer): wire the gate into `_MatureStoriesEntry` (about 3h)
- `complete_stories_screen.dart`: `initState` uses `storedBirthYear` only. On tap, call `resolve`:
  - `adult`: push the mature screen.
  - `minor`: hide the tile for the session and show the snackbar `matureStoriesUnavailable`.
  - `askBirthYear`: push `AgeCheckScreen`, store the answer, then decide with `isAdult`.
- Allow an optional `AgeGate` to be injected for widget tests.
- Leave `age_check_screen.dart`, including its uncommitted styling change, untouched.
- No new strings are expected. If any are added, put them in both arb files and run `flutter gen-l10n`.
- **Acceptance criteria:**
  - Widget tests with a fake gate cover all three verdicts.
  - The UI doesn't block: the spinner shows during the check and taps are ignored while it runs.
  - The birth-year screen appears only for `askBirthYear`.

### F2 (frontend-developer, plus Luca for the portal): native setup (about 2h)
- Create `ios/Runner/Runner.entitlements` with `com.apple.developer.declared-age-range` set to true, and set `CODE_SIGN_ENTITLEMENTS` for Debug, Release and Profile in `project.pbxproj`.
- Luca: enable "Declared Age Range" on the App ID, then regenerate the match profiles locally (`fastlane match appstore --force`), because CI runs match in readonly mode.
- Android needs no changes.
- **Acceptance criteria:** the release IPA's entitlements contain the key (`codesign -d --entitlements`), and the deploy workflow passes.

### QA (Luca, about 4h)
- Android: a debug build with `useMockData` (temporary local flag), and a license tester on the internal track.
- iOS: a device on 26.2+ with sandbox Age Assurance scenarios, plus a device below 26 to check the fallback.

**Total effort:** about 14h, or 2 days including QA.

## Impact
- **Files:** pubspec.yaml and pubspec.lock; 2 new services; `complete_stories_screen.dart`; 3 or 4 test files; `Runner.entitlements` (new); `project.pbxproj`.
- **No changes:** firestore.rules, functions, build.gradle, Info.plist.
- **CI:** `ci.yml` is unaffected (tests use fakes). `deploy.yml` (macos-15, `latest-stable` Xcode) needs Xcode 26.2 or later to compile the Declared Age Range code paths. Check the runner image. With an older SDK the plugin throws `UnsupportedPlatform` and we fall back.
- **Stores:**
  - Play Data safety: the age range is processed on the device and not transmitted, so no new "collected" data type is expected. Confirm against the Age Signals API terms, which allow use only for age-appropriate experiences, which is what we do.
  - App Store: the capability must be enabled on the App ID. Mention the age-range use in the review notes. The privacy label is unchanged because the data isn't collected.

## Risks
1. **Beta APIs and a young plugin (0.x).** The API surface has already changed (a field was renamed in 0.8). Mitigation: pin `^0.10.1` and keep the plugin isolated behind `AgeSignalsSource`.
2. **Limited Play coverage until the end of 2026.** Most Android users will still see the birth-year screen. This is expected, and the behaviour is safe.
3. **iOS capability or provisioning problems.** A missing capability makes the plugin throw `MissingEntitlementException`, which maps to `unavailable` (fallback), so the app stays safe.
4. **A sheet or hang blocking the UI.** Mitigation: the 20s timeout, the spinner, and no calls from `initState`.
5. **A late result after a timeout is ignored,** so the user may see the birth-year screen while the system sheet is still closing. Rare, and acceptable.

## Open question
Should Android `tierB` (parent-managed) be treated as minor even when the reported range is 18+? This plan assumes yes, as the safer choice.

## Update after device testing (2026-10-10)

On an iPhone in Italy, Declared Age Range answers `notAvailable` (`ApiNotAvailableException`) even with the entitlement correctly signed, after showing Apple's "Age-appropriate experience in apps" sheet. Because "unavailable" was never cached, that sheet reappeared on every tap, including for users who had already entered an adult birth year.

`PluginAgeSignalsSource` now treats `ApiNotAvailableException`, `UnsupportedPlatformException` and `MissingEntitlementException` as permanent for the app run: the platform isn't asked again until the next launch. Transient failures (network, cancellation, API errors, timeouts) are still retried on the next tap.
