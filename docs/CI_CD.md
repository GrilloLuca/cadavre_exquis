# CI/CD — GitHub Actions + fastlane

## Workflows (`.github/workflows/`)

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` — **CI** | every pull request | `flutter analyze` + `flutter test` |
| `deploy.yml` — **Deploy beta** | push to `master` (or run manually) | test → **Play internal track** + **TestFlight** |
| `release.yml` — **Release** | manual: Actions ▸ Release ▸ *Run workflow* | promotes internal → **Play production** and/or submits the TestFlight build for **App Store review** (no rebuild) |
| `bump-version.yml` — **Bump version** | manual: Actions ▸ Bump version ▸ *Run workflow* | bumps the version name in `pubspec.yaml` (patch / minor / major) and opens a PR; merging it deploys the new version to beta |

Watch runs in the **Actions** tab of the GitHub repo. Build numbers are automatic (latest in store + 1);
the version name comes from `pubspec.yaml` (`version: 1.0.0+1` → `1.0.0`) — bump it for each store release.

## One-time setup

### 1. iOS signing with match (run locally on your Mac)
1. Create an empty **private** GitHub repo for certificates, e.g. `GrilloLuca/ios-certificates`.
2. Create an **App Store Connect API key** (App Store Connect ▸ Users and Access ▸ Integrations ▸ App Store Connect API, role *App Manager*) and download the `.p8`.
3. Generate certs/profiles:
   ```sh
   cd ios
   bundle install
   export MATCH_GIT_URL=https://github.com/GrilloLuca/ios-certificates.git
   export MATCH_PASSWORD='<choose a strong passphrase>'
   export ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_CONTENT=$(base64 -i AuthKey_XXXX.p8)
   bundle exec fastlane ios certs
   ```
   Xcode can keep automatic signing locally — CI switches to the match profile only during its build.
4. Make sure the app exists in App Store Connect (bundle ID `com.lucagrillo.cadavreexquis`).

### 2. Android
1. Use the upload keystore referenced by `android/key.properties`.
2. The Google Play service account (`android/fastlane/play-store-credentials.json`) needs *Release* permissions on the app.
3. The **first** AAB must be uploaded manually in Play Console. While the app is still a *draft*, add the repo variable `PLAY_RELEASE_STATUS=draft`.

### 3. GitHub secrets (repo ▸ Settings ▸ Secrets and variables ▸ Actions ▸ *New repository secret*)

| Secret | Value |
|---|---|
| `GOOGLE_SERVICES_JSON` | paste contents of `android/app/google-services.json` |
| `GOOGLE_SERVICE_INFO_PLIST` | paste contents of `ios/Runner/GoogleService-Info.plist` |
| `PLAY_STORE_JSON_KEY` | paste contents of the Play service account JSON |
| `ANDROID_KEYSTORE_BASE64` | `base64 -i upload-keystore.jks \| pbcopy` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password |
| `ASC_KEY_ID` | API key ID |
| `ASC_ISSUER_ID` | issuer ID |
| `ASC_KEY_CONTENT` | `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `MATCH_GIT_URL` | HTTPS URL of the certificates repo |
| `MATCH_PASSWORD` | match passphrase |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `echo -n 'GrilloLuca:<PAT>' \| base64 \| pbcopy` — fine-grained PAT with *Contents: read* on the certificates repo |

Optional repo **variables** (same page, *Variables* tab): `PLAY_RELEASE_STATUS` (`draft`/`completed`), `IOS_AUTOMATIC_RELEASE` (`true` = release automatically after approval).

## Running lanes locally
```sh
cd android && bundle exec fastlane android internal     # or: production
cd ios     && bundle exec fastlane ios beta              # or: release, certs
```

## Notes
- Run **Release** for iOS after the TestFlight build has finished processing (usually 10–30 min).
- Cost: free for public repos. Private repos get 2,000 free minutes/month, and macOS minutes count 10×, so an iOS build (~15–20 min) uses ~150–200 of them.
- Pin Flutter: replace `channel: stable` with `flutter-version: <your version>` in the workflows for reproducible builds.

## Releasing a new version
1. **Actions ▸ Bump version ▸ Run workflow**, choose `patch` (1.0.0 → 1.0.1), `minor` (→ 1.1.0) or `major` (→ 2.0.0).
2. Review and merge the PR it opens → **Deploy beta** uploads the new version to Play internal + TestFlight.
3. Test, then **Actions ▸ Release ▸ Run workflow** to send it to production / App Store review.

Locally: `cd android && bundle exec fastlane android bump type:minor` (edits `pubspec.yaml`, no commit).
One-time setting needed for the PR step: repo **Settings ▸ Actions ▸ General ▸ Workflow permissions** →
tick **"Allow GitHub Actions to create and approve pull requests"**.
