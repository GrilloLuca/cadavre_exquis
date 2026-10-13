# Push notifications: technical analysis

**User story.** As a player, I want a push notification when someone adds a part to a story I wrote, so that I can continue the story or read it once it's complete.

**Status:** implemented on `feature/push-notifications` (see §11 for what differs from the analysis and the manual steps left). Target: Android + iOS. Web is out of scope (see §9).

---

## 1. What triggers a notification

A story has 4 parts (`kStoryPositions`). Each part is written by a player identified by their auth email (`parts[].author`), and the same player can write several parts, just not two in a row. So a story produces at most 3 "continued" events and 1 "completed" event, which keeps the volume low and means no batching or digest is needed.

| Event | When it is detected | Who receives it | Tap opens |
|---|---|---|---|
| **Story continued** (`story_continued`) | `stories/{id}` update where `parts` grew by one **and** `status` is still `incomplete` | Distinct authors of the earlier parts, excluding the new author and anonymized (`""`) authors | The story's writing screen (`ChatScreen`), if it is still free |
| **Story completed** (`story_completed`) | After the AI review has saved `mature`/`title` (`reviewCompletedStory`) | Distinct authors of every part except the one who wrote the last part | The story's reading screen (`StoryReadScreen`), behind the age gate if `mature` |

Why "completed" waits for the review instead of firing on `status → complete`:
- The completed list only shows reviewed stories (`completeStoriesStream` filters `mature in [false, true]`), so a notification sent earlier would open a story the app doesn't list yet.
- The notification can then include the AI title, which is always suitable for a 10-year-old (`REVIEW_INSTRUCTION`). A "continued" notification has no title yet.
- If the review fails, the story stays hidden and no notification goes out. That matches what the app shows today (known gap, see [[mature-stories-moderation]]).

The last author is not notified on completion. They have just finished the story, and the chat screen can tell them it will appear in the list shortly. *(Open decision D4.)*

**Content rule:** notifications **never contain story text**. Players are mostly children, a lock screen is visible to anyone, and part text is not moderated until completion. "Continued" shows the new author's nickname (already public in the app), and "completed" shows the AI title.

Example strings (localized server-side, see §4.3):
- IT: "**Marta** ha continuato una tua storia ✍️ / Tocca per scrivere il prossimo pezzo." · "**Il drago del faro** è completa! 📖 / Tocca per leggerla."
- EN: "**Marta** continued one of your stories ✍️ / Tap to write the next part." · "**The lighthouse dragon** is complete! 📖 / Tap to read it."

---

## 2. Architecture overview

```
 Device A (writer)                Firestore                 Cloud Functions                FCM           Device B (earlier author)
 submitPart ─────────────▶ stories/{id} updated ──▶ notifyStoryContinued ──▶ send ──▶ notification
                                                     (reads pushTokens by emailKey)            │ tap
                                                                                               ▼
                                                    reviewCompletedStory                 app opens → HomeScreen
                                                     └▶ saveReview → notifyStoryCompleted      → ChatScreen / StoryReadScreen
 App start / sign-in ──▶ pushTokens/{fcmToken} {emailKey, locale, platform, updatedAt}
 Sign-out ─────────────▶ delete pushTokens/{fcmToken}
```

Sending stays on the server. The client only registers its token: a client can't be trusted to notify other users, and the rules already make the server the authority on stories.

---

## 3. Data model

### `pushTokens/{fcmToken}` (new collection)

| Field | Type | Notes |
|---|---|---|
| `emailKey` | string | `emailKey(email)`, lowercase, same key as `userProfiles` |
| `locale` | string | App UI language (`it`/`en`) at the last registration, used to localize the notification |
| `platform` | string | `android` / `ios`, for diagnostics |
| `updatedAt` | timestamp | `request.time`, refreshed on each app start, used for pruning stale tokens |

**Why keyed by token** (and not `userProfiles/{emailKey}/devices/{token}`):
- A device has one token. If a second account signs in on the same device, its write overwrites the owner, so the previous account stops receiving that device's notifications without any extra cleanup.
- One account on several devices gets one doc per device, found with `where('emailKey', '==', key)`. That is a single-field query, so the automatic index covers it.
- It keeps the `userProfiles` rules (nickname set once, `keys().hasOnly(['nickname','updatedAt'])`) untouched.

`parts[].author` holds the email as typed at sign-in, so the function looks up `emailKey(author)`. It must lowercase and trim exactly like `lib/domain/models/email_key.dart` and `anonymizeParts` do.

### Security rules

```
match /pushTokens/{token} {
  function isValidToken() {
    let d = request.resource.data;
    return d.keys().hasOnly(['emailKey', 'locale', 'platform', 'updatedAt'])
      && d.emailKey == myEmail().lower()
      && d.locale is string && d.locale.size() <= 10
      && d.platform in ['android', 'ios']
      && d.updatedAt == request.time;
  }
  // Writing a token claims it for the signed-in user. A token is only known
  // to its device, and taking over a device's token is exactly what a new
  // sign-in on that device should do.
  allow create, update: if signedIn() && isValidToken();
  allow delete: if signedIn() && resource.data.emailKey == myEmail().lower();
  allow read: if false;   // only the Admin SDK reads tokens
}
```

---

## 4. Backend (`functions/src/index.ts`)

### 4.1 `notifyStoryContinued`: new `onDocumentUpdated("stories/{storyId}")`

```ts
const before = event.data?.before.data(); const after = event.data?.after.data();
if (!before || !after) return;
const n = (before.parts ?? []).length;
if ((after.parts ?? []).length !== n + 1 || after.status !== "incomplete") return;
const newAuthor = after.parts[n].author;
const recipients = recipientsFor(after.parts.slice(0, n), newAuthor); // distinct emailKeys, minus newAuthor and ""
```

Next it reads the new author's nickname from `userProfiles/{key}`, falling back to a localized "Someone" (`authorDisplayName` in the app masks the email, but a notification should not show even a masked email). Then it calls `sendToUsers(recipients, message)`.

This is a separate function from `reviewCompletedStory` even though both watch the same document. That keeps each one small and lets each fail independently, and it matches the file's existing one-trigger-per-concern style.

### 4.2 `notifyStoryCompleted`: called from `reviewCompletedStory`

`saveReview` returns whether **this run** set `mature`, so it returns `true` only the first time. `reviewCompletedStory` calls `notifyStoryCompleted(storyId)` only in that case:
- If the event is delivered twice, the second run finds `mature` already set and sends nothing.
- `functions/scripts/review-complete-stories.js` (the backfill) calls `reviewStory`/`saveReview` directly and never the trigger, so re-running it never spams old authors. Add a comment there so this stays true.

### 4.3 Shared helpers (exported pure functions, like `missingRoomFields` / `anonymizeParts`)

- `recipientsFor(parts, excludeAuthor): string[]`: distinct, normalized emailKeys.
- `messageFor(kind, locale, {nickname?, title?})`: a `{title, body}` string table for `it` and `en`, with `en` as fallback for unknown locales. These are the only user-visible strings outside the ARB files. Keep them together in one `NOTIFICATION_STRINGS` object, mirroring the ARB keys.
- `sendToUsers(emailKeys, build)`:
  1. Queries `pushTokens` with `where("emailKey", "in", chunk)`, in chunks of 30. There are at most 3 recipients, so in practice one query.
  2. Builds one message per token in that token's locale and sends with `getMessaging().sendEach(messages)`.
  3. For responses with `messaging/registration-token-not-registered` or `invalid-registration-token`, deletes that `pushTokens` doc.
  4. Logs the counts (sent/failed/pruned) and never throws. A notification failure must not fail or retry the trigger.

### 4.4 Message shape

```ts
{
  token,
  notification: { title, body },                     // OS shows it when app is background/terminated
  data: { type: "story_continued" | "story_completed", storyId },
  android: { notification: { channelId: "story_updates", tag: `story-${storyId}` , icon: "ic_stat_notify" } },
  apns: { headers: { "apns-collapse-id": `story-${storyId}` }, payload: { aps: { sound: "default" } } },
}
```

`tag` / `apns-collapse-id` per story means the device keeps only the latest notification for a story. A newer "continued" replaces an older one, and "completed" replaces the last "continued". This also hides any duplicate from at-least-once trigger delivery, so no event-id dedupe collection is needed.

### 4.5 Account deletion

`anonymizeDeletedUser` also deletes `pushTokens` where `emailKey == key`. It adds one query and uses the existing `bulkWriter`.

### 4.6 Stale tokens

Tokens are pruned on send failure (§4.3). Optionally, a weekly `onSchedule` function can delete tokens with `updatedAt` older than 90 days, for uninstalled apps that never received a send. It's not needed for v1.

### 4.7 Function tests

`functions/` has no test runner today. Add `node:test` (no new dependency) for `recipientsFor` and `messageFor`, and an `npm test` script. Test the triggers manually with the Firestore + Functions emulators. FCM can't be emulated, so the last step is a real device.

---

## 5. App (Flutter, MVVM)

### 5.1 Dependencies and platform setup

- `firebase_messaging` (FlutterFire, same major family as `firebase_core ^4`). **No** `flutter_local_notifications` in v1 (see §5.5).
- **Android:** a monochrome `ic_stat_notify` drawable plus `default_notification_icon`/`default_notification_channel_id` meta-data in `AndroidManifest.xml`. Create the `story_updates` channel. `firebase_messaging` creates a default one, but a named channel shows "Story updates" in system settings, which needs a small native snippet in `MainActivity` or a plugin. On Android 13+ the `POST_NOTIFICATIONS` runtime permission is requested via `FirebaseMessaging.requestPermission()`.
- **iOS:** in Xcode, the *Push Notifications* capability (adds `aps-environment` to `Runner.entitlements`) and *Background Modes → Remote notifications*. Upload an **APNs auth key (.p8)** to Firebase Console → Cloud Messaging. Check that the Fastlane/`release.yml` provisioning profile includes push. The profile has to be regenerated once the capability is added, otherwise the iOS release build fails to sign.

### 5.2 Layers

| File | Role |
|---|---|
| `lib/data/services/push_messaging_service.dart` | Thin wrapper over `FirebaseMessaging`: `requestPermission`, `getToken`, `onTokenRefresh`, `deleteToken`, `getInitialMessage`, `onMessageOpenedApp`, `onMessage`. The only file that imports the SDK. |
| `lib/domain/models/story_notification.dart` | `enum StoryNotificationKind { continued, completed }`, `class StoryNotification { kind, storyId, title?, body? }`, and `StoryNotification? fromData(Map<String, String>)` so payload parsing is testable without the SDK. |
| `lib/data/repositories/notification/notification_repository.dart` | Interface: `Future<NotificationPermission> permission()`, `Future<bool> requestPermission()`, `Future<void> register({required String email, required String locale})`, `Future<void> unregister()`, `Stream<StoryNotification> opened` (taps), `Stream<StoryNotification> received` (foreground), `StoryNotification? takeInitial()`. |
| `…/notification_repository_firebase.dart` | Implementation. It writes/deletes `pushTokens/{token}` and re-registers on `onTokenRefresh`. It **buffers the launch notification** (from `getInitialMessage`) until `takeInitial()` is called, because it arrives before `HomeScreen` exists. |
| `testing/fakes/repositories/fake_notification_repository.dart` | In-memory fake with a `StreamController` to simulate taps in widget tests. |
| `lib/data/repositories/story/…` | Adds `Future<Story?> getStory(String id)`. The repo has no single-story fetch today, and a notification only carries the id. |
| `lib/config/dependencies.dart` | Provides `NotificationRepository`, below `AuthRepository`. |

`test/architecture_test.dart` needs nothing new. The SDK stays in `data/services`, and the UI sees only the interface.

### 5.3 Registration lifecycle

- **Sign-in / app start while signed in:** if permission is already granted, `register(email, locale)`, which also refreshes `updatedAt` and `locale`. This is triggered by the repository listening to `AuthRepository`, the same pattern as `RoomRepository` and `AgeGate`.
- **Sign-out:** must unregister **before** `signOut()`, because deleting the token doc needs the user's auth. Today `AccountViewModel.signOut` is `Command0(_auth.signOut)`. It becomes `() async { await _notifications.unregister(); await _auth.signOut(); }`, where unregister is best-effort: it swallows its own errors so it can never block sign-out. Without this, the next person to sign in on that device would get the previous user's notifications until their own `register` overwrites the doc.
- **Delete account:** the server cleans up (§4.5), and the client also calls `deleteToken()` locally.
- **Token refresh:** handled inside the repository.

### 5.4 When to ask for permission

Don't ask at startup. Ask **in context, right after the player submits their first part** (`ChatViewModel.submit` succeeds), when the value is obvious. A short in-app explainer comes first ("Want to know when someone continues your story?" with *Yes* / *Not now*), and the OS prompt only follows *Yes*. iOS gives an app one system prompt, so it shouldn't be spent blind.
- "Not now" is remembered in shared_preferences (`notificationPromptDismissedAt`) and asked again after N submits or days. *(D3)*
- The **Account** screen gets a "Notifications" row showing the current state. If it's off and the OS permission was denied, the row explains how to enable it in system settings.

### 5.5 Handling notifications in the app

| App state | What happens |
|---|---|
| Terminated → tap | `getInitialMessage` → buffered → `HomeScreen` consumes it via its ViewModel after mount |
| Background → tap | `onMessageOpenedApp` → `opened` stream → `HomeViewModel` → View navigates |
| Foreground | FCM shows nothing on Android (and nothing on iOS unless configured). Show an in-app **SnackBar** with an *Open* action instead. Skip it if the user is already on that story. No local-notification plugin is needed. |

Routing happens in **`HomeScreen`**, the first screen that only exists while signed in. Pending notifications are ignored while signed out (the user may have switched account).

- `HomeViewModel` gets `NotificationRepository` + `StoryRepository` and a `Command1<StoryLink?, StoryNotification> openNotification` that fetches the story and decides:
  - **continued:** story still `incomplete`, not `wasLastWrittenBy(me)`, not `isLockedFor(me)` → `StoryLink.write(story)`. Otherwise → `StoryLink.unavailable(reason)`, shown as a SnackBar ("Someone is already writing this part" / "This story is already complete", reusing the existing `StoryErrorCode` l10n). `ChatScreen` takes the lock itself, so a race after the check is handled by the existing lock error path.
  - **completed:** story `complete` and reviewed → `StoryLink.read(story)`. If `mature == true`, the age gate runs first, reusing the `CompleteStoriesViewModel.unlock → AgeCheckScreen → submitBirthYear` flow (factor the decision out of `CompleteStoriesViewModel` instead of duplicating it).
- The View pushes `ChatScreen(story:)` / `StoryReadScreen(story:)` with `MaterialPageRoute`, as `incomplete_stories_screen.dart` and `complete_stories_screen.dart` do.
- **Room:** the story may belong to a different language room or a private room the user has since left. Stories are readable by any signed-in user (rules), so the screens are opened directly **without switching the current room**. That avoids needing the private room password. *(D5)*

### 5.6 Localization

New ARB keys in `app_it.arb` + `app_en.arb`: permission explainer (title, body, yes, not now), Account row (title, on/off/denied states), foreground SnackBar texts and action, and the "story unavailable" messages not already covered. The **push texts themselves live server-side** (§4.3), because the server builds them.

---

## 6. Privacy, minors and store policy

- **Children:** the audience is mostly kids and teens. The notifications are transactional (a reaction to the user's own activity), never marketing, and contain no story text. Check against **Google Play Families policy** and the App Store guidelines for apps used by children before release; FCM is generally allowed for this use. *(D1)*
- Update the **privacy policy** (`hosting/`) and the **Play Data safety form**: device push tokens are collected, linked to the account, used for app functionality, and deleted on sign-out or account deletion.
- The token doc stores the `emailKey`, which is already the key of `userProfiles`. No new personal data is involved.

---

## 7. Testing plan

- **Dart unit:** `StoryNotification.fromData` (valid, unknown type, missing id); `HomeViewModel.openNotification` decision table (incomplete/free, locked by other, last written by me, complete+reviewed, complete+mature, story not found); `AccountViewModel.signOut` unregisters before signing out, and still signs out if unregister fails; `getStory`.
- **Widget:** a tap from `FakeNotificationRepository` on `HomeScreen` pushes `ChatScreen` / `StoryReadScreen`, a launch notification is consumed once, and the foreground SnackBar appears.
- **Functions:** `recipientsFor` (dedupe, case, excludes new author and `""`), `messageFor` (locale fallback).
- **Rules:** a user can't write a token with someone else's `emailKey`, extra keys are rejected, delete is owner-only, read is denied.
- **Manual (real devices, both platforms):** 2 accounts on 2 devices; continued and completed notifications in all three app states; sign-out stops delivery; second account on the same device; Android 13 permission denial; iOS release build signs with push.

---

## 8. Rollout

1. **Backend first:** rules + `notifyStoryContinued` + `notifyStoryCompleted` + account-deletion cleanup. Harmless while no app registers tokens, since `pushTokens` is empty.
2. **APNs key** in Firebase Console; iOS capability and provisioning profile.
3. **App release** (patch bump via `commit-message`). Older app versions simply never register.
4. Watch the function logs for sent/failed/pruned counts during the first week.

Rough effort: backend ~1 day, app ~2–3 days (most of it permission UX, routing and tests), platform/store setup ~0.5 day plus review time.

---

## 9. Out of scope (v1)

- **Web push** (needs a VAPID key, `firebase-messaging-sw.js`, and a different permission UX). The web build isn't a primary target.
- Per-type preferences (e.g. only "completed"). v1 has one on/off.
- Notifications to players who never wrote in the story (e.g. "new story in your room").
- In-app notification inbox/badge counts.
- Quiet hours. Volume is low (≤ 4 per story), but D2 may change that.

---

## 10. Open decisions

| # | Question | Recommendation |
|---|---|---|
| D1 | Do any store/minor policies restrict push for under-13s in our setup? | Check Play Families + App Store before release. Keep payloads content-free regardless. |
| D2 | Quiet hours (e.g. no pushes 21:00–08:00 local)? | Not in v1. If wanted, store the UTC offset on the token and defer the send with Cloud Tasks. |
| D3 | When to re-ask after "Not now"? | After the 3rd submitted part or 7 days, whichever comes first, at most twice. |
| D4 | Notify the last author on completion too? | No. Instead, show "it'll appear in the list in a moment" after the final submit. |
| D5 | Should tapping switch the Home room to the story's room? | No, open the story screen directly. Revisit if users get confused coming back. |
| D6 | Show the new author's nickname in "continued"? | Yes. It's already public in the app, and it makes the push feel social. |

---

## 11. Implementation notes

The decisions D2–D6 follow the recommendations above; D3 is simplified to "offer until the second *Not now*, at least 7 days apart" (`NotificationOfferPolicy`).

**Where things are**

| Piece | File |
|---|---|
| Triggers, texts, sending, token pruning | `functions/src/notifications.ts` (+ `notifyStoryContinued`, the `reviewCompletedStory` hook and token deletion in `anonymizeDeletedUser`, in `index.ts`) |
| Function tests | `functions/test/notifications.test.js` (`npm test`) |
| Rules | `pushTokens/{token}` in `firestore.rules` |
| FCM wrapper | `lib/data/services/push_messaging_service.dart` |
| "Not now" memory | `lib/data/services/notification_offer_preference.dart` |
| Repository | `lib/data/repositories/notification/` (+ fake in `testing/fakes/repositories/`) |
| Tap routing | `NotificationRouterViewModel` (`lib/ui/home/view_models/`), driven by `HomeScreen` |
| Offer after sending a part | `ChatViewModel.offerNotifications` / `answerNotificationOffer`, `NotificationOfferDialog` |
| Profile card | `NotificationsCard`, `AccountViewModel.enableNotifications` |
| Android | `MainActivity.java` (channel `story_updates`), `res/drawable/ic_stat_notify.xml`, `res/values*/strings.xml`, manifest meta-data |
| iOS | `aps-environment` in `Runner.entitlements`, `remote-notification` background mode in `Info.plist` |

**Differences from the analysis**
- The routing lives in its own `NotificationRouterViewModel` next to `HomeViewModel` instead of inside it, so the home ViewModel stays about rooms.
- The mature-story age check in the router repeats the short `AgeGate` sequence of `CompleteStoriesViewModel.unlock` rather than extracting it; both share the verdicts through `AgeGate`.
- `firebase_messaging` is pinned to `^16.4.3`, the release matching the `firebase_core` 4.12.1 in the lockfile: the latest (16.7.0) pulls `firebase_core` 4.15, which no longer compiles with the locked `firebase_auth` 6.5.6. Upgrade the FlutterFire packages together later.

**Manual steps before release**
1. Apple Developer portal: enable *Push Notifications* on the App ID, create an **APNs auth key (.p8)** and upload it in Firebase Console → Project settings → Cloud Messaging.
2. Regenerate the App Store profile so it includes push: `fastlane match appstore --force` (CI runs match read-only, so it can't do it).
3. Deploy the backend first: `firebase deploy --only firestore:rules,functions`.
4. Update the privacy policy (`hosting/`) and the Play Data safety form (device push token, linked to the account, deleted on sign-out/account deletion). Check D1.
5. Test on real devices (§7, manual list).

