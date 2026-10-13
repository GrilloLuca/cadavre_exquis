# Migration to MVVM (official Flutter app architecture guide)

Status: done (2026-10-13), Phases 0–3 and 5 on `feature/mvvm-migration`; Phase 4 (go_router) postponed. Target: https://docs.flutter.dev/app-architecture/guide. The resulting conventions are in `docs/ARCHITECTURE.md`.

How to use this file: tick a task when its PR is merged, add a line to the [Progress log](#progress-log), and record any decision under [Decisions](#decisions). One feature per PR, no behaviour change, existing tests stay green.

## 1. Current architecture (as of 2026-10-12, master `aa380ac`)

A light layered architecture with **logic in `StatefulWidget`s**: no state-management library, no dependency injection, no ViewModels.

``` 
screens/   StatefulWidget: UI + state + logic + navigation + error mapping
   │  instantiate directly
   ▼
services/  Firestore / Auth / SharedPreferences access + some domain rules
   │
   ▼
models/    Story, PrivateRoom… coupled to Firestore and partly to Flutter
```

State: `setState`, `StreamBuilder`, callbacks passed down (`HomeScreen` → `AccountScreen` via `onLanguageChanged` / `onPrivateRoomChanged`). Navigation: named routes + `Navigator.push`; `AuthWrapper` listens to `FirebaseAuth.authStateChanges()`.

### Already aligned with the guide (keep)
- Services throw **coded exceptions** (`StoryServiceErrorCode`, `PrivateRoomServiceErrorCode`, `UserProfileServiceErrorCode`) and the UI maps them to l10n strings: no user-facing text in the data layer.
- `StoryService`, `UserProfileService`, `AgeCheckService`, `AgeGate` already take injectable dependencies (`firestore`, `now`, `clock`) and are tested with `fake_cloud_firestore`.
- `AgeGate` is effectively a domain **use case** (combines two data sources, no UI).
- Turn rules (`wasLastWrittenBy`, `isLockedFor`) live in the model, not the UI.

### Gaps
| Problem | Where |
|---|---|
| Business logic in views | `chat_screen.dart` (lock acquire/release in `dispose`), `complete_stories_screen.dart` (age-gate flow), `home_screen.dart` (language room resolution, private room state) |
| `FirebaseAuth.instance` used directly in screens | `chat_screen`, `incomplete_stories_screen`, `create_private_room_screen`, `login_screen`, `registration_screen`, `complete_stories_screen`, `account_screen` |
| Services created inside widgets, no DI | `ChatScreen` (`StoryService()`), `IncompleteStoriesScreen`, `Join/CreatePrivateRoomScreen` (`PrivateRoomService` is not even injectable) |
| Static services / state | `AuthService` (static only), `AgeGate._sessionSignals` static cache |
| Models depend on data layer and UI | `Story`/`StoryPart` use `Timestamp` and `fromSnapshot`; `positionLabel(BuildContext)` is in `models/story.dart` |
| Shared state threaded by hand | private room and language live in `_HomeScreenState` and go down via callbacks |
| Oversized screens | `account_screen.dart` (854 lines), `complete_stories_screen.dart` (408) |
| Folders by technical type | shared widgets (`button.dart`, `cream_card.dart`, `background.dart`, `message_bubble.dart`, `typing_indicator.dart`) at the root of `lib/` |

In short: today's `services/` play the guide's **Repository** role (source of truth + rules); the screens are both **View** and **ViewModel**.

## 2. Target architecture

```
lib/
  config/dependencies.dart          # providers (DI)
  data/
    repositories/                   # source of truth: abstract + Firestore impl
      story/  auth/  user_profile/  private_room/  age_check/  room/
    services/                       # stateless wrappers over external APIs
      age_signals_service.dart, shared_preferences_service.dart, google_sign_in_service.dart
  domain/
    models/                         # pure Dart (DateTime, no Firestore types)
    use_cases/                      # AgeGate (the age check, D2)
  ui/
    core/                           # theme, AppColors, shared widgets, l10n error mapping
    <feature>/view_models/  <feature>/widgets/
  routing/                          # optional, go_router
  utils/ result.dart, command.dart
testing/fakes/                      # FakeStoryRepository, …
```

### Mapping
| Today | Target |
|---|---|
| `StoryService` | `StoryRepository` (abstract) + `StoryRepositoryFirestore`. The Firestore SDK is already the "service": no extra wrapper |
| `AuthService` (static) + `FirebaseAuth.instance` | `AuthRepository extends ChangeNotifier` (`currentUserEmail`, sign-in, `signOut`, `deleteAccount`) + `GoogleSignInService` |
| `UserProfileService` | `UserProfileRepository`; nickname validation → `domain/` |
| `AgeCheckService` + `AgeGate` | `AgeCheckRepository` + `AgeGate` use case in `domain/use_cases/` (name kept); session cache becomes per-instance, cleared on sign-out |
| `LanguageRoomPreference` + `HomeScreen` state | `SharedPreferencesService` + `RoomRepository` (ChangeNotifier: current language + private room), removing the callbacks |
| `PrivateRoomService` | `PrivateRoomRepository` |
| `_XxxScreenState` with logic | `XxxViewModel extends ChangeNotifier`, async actions as `Command`s |

Pilot sketch:

```dart
class ChatViewModel extends ChangeNotifier {
  ChatViewModel({required StoryRepository stories, required AuthRepository auth, required this.story})
      : _stories = stories, _auth = auth {
    lock = Command0(_lock)..execute();
    submit = Command1<void, String>(_submit);
  }
  late final Command0 lock;
  late final Command1<void, String> submit;
  bool get canWrite => _lockAcquired && !submit.running;
  @override
  void dispose() { if (_lockAcquired) unawaited(_stories.unlockStory(...)); super.dispose(); }
}
```

The view listens to the commands, shows snackbars and pops on completion/error. Only widgets and navigation remain in the view.

## 3. Roadmap

### Phase 0: foundations (1 PR)
- [x] Add `provider`; add `Command0`/`Command1` in `lib/utils/command.dart` (adapted from the guide's *compass_app* to catch exceptions, see D1; tests in `test/command_test.dart`)
- [x] Create `lib/ui/core/{themes,ui}` and `lib/utils`; move `AppColors`, `constants.dart` to `ui/core/themes/`, shared widgets (`Background`, `ChatButton`, `CreamCard`, `MessageBubble`, `TypingIndicator`) to `ui/core/ui/`, theme from `main.dart` to `AppTheme` in `ui/core/themes/theme.dart`. `config/`, `data/`, `domain/` are created when Phase 1–2 add their first file
- [x] Decide D1 (exceptions vs `Result`), record it below
- [x] Decide D2 (domain layer scope), record it below

### Phase 1: data layer and models (2–3 PRs)
- [x] Pure-Dart models in `lib/domain/models/`: `Timestamp` → `DateTime`; Firestore mapping in `data/repositories/story/story_firestore_mapping.dart`; `positionLabel` → `ui/core/position_label.dart`
- [x] Abstract repositories + Firestore impls from current services (moved with `git mv`, logic unchanged): `StoryRepository`, `UserProfileRepository`, `AgeCheckRepository`, `PrivateRoomRepository` (now injectable, `firestore:` param). Screens take the abstract type and default to the Firestore impl until Phase 2 adds providers
- [x] Domain errors and rules out of the services: `StoryException`/`StoryErrorCode`, `PrivateRoomException`/`PrivateRoomErrorCode`, `UserProfileException`/`UserProfileErrorCode` (the `Service` infix dropped) in `domain/models/`; `Nickname` (normalize/validate/min/max), `emailKey()`, `AgeRules` (isAdult/adultAge/oldestBirthYear)
- [x] `age_signals_source.dart` → `data/services/`
- [x] Fakes in `testing/fakes/repositories/` (story, user profile, age check, private room); `test/fake_story_repository_test.dart` checks the story fake follows the turn rules. Service tests renamed to `*_repository_firestore_test.dart`
- Left in `lib/services/` on purpose: `auth_service.dart` (→ Phase 2, done), `language_room_preference.dart` (→ Phase 3 with `RoomRepository`, done: now in `data/services/`), `age_gate.dart` (→ Phase 3, use case, D2, done: now in `domain/use_cases/`). `lib/services/` is gone

### Phase 2: auth and central DI (1 PR)
- [x] `AuthRepository` (ChangeNotifier) + `AuthRepositoryFirebase` replace static `AuthService`; Google SDK behind `data/services/google_sign_in_service.dart`; Firebase errors become `AuthException`/`AuthErrorCode` (`domain/models/auth_error.dart`, D1). `config/dependencies.dart` provides all repositories via `MultiProvider` in `main.dart`; screens `context.read` them (optional constructor params kept for existing tests until Phase 3). `AgeGate` now requires its `storage`
- [x] `AuthWrapper` watches `AuthRepository`; no `firebase_auth`, `google_sign_in` or `*RepositoryFirestore()` outside `lib/data` and `lib/config`. `FakeAuthRepository` in `testing/fakes/`; `test/auth_wrapper_test.dart`

### Phase 3: ViewModels, one feature per PR (simplest to riskiest)
- [x] `ChatScreen` (pilot): `ui/chat/view_models/chat_view_model.dart` (`lock` Command0 started on creation, `submit` Command1<bool, String> whose value is true only when a part was stored; unlock on `dispose`) + `ui/chat/widgets/chat_screen.dart` (only listens to the commands: pop/snackbar on lock error, snackbar on submit error, pop on submit). The screen creates its ViewModel in `initState` and disposes it. Tests in `test/ui/chat/`, including a regression test that rebuilds the app with the chat open
- [x] `IncompleteStoriesScreen`: `IncompleteStoriesViewModel` keeps one stream subscription per room (`setRoom` on room change; before, the stream was re-requested on every rebuild), sorts the list, exposes `statusOf(story)` (available / being written / waiting for others, computed at read time so expired locks free up) and a `createStory` command. Moved to `ui/incomplete_stories/`. Tests in `test/ui/incomplete_stories/`
- [x] `JoinPrivateRoomScreen` / `CreatePrivateRoomScreen`: `JoinPrivateRoomViewModel` (`join` command) and `CreatePrivateRoomViewModel` (`create` command, value null when nobody is signed in); form validation stays in the Views (presentation, needs l10n). The two forms and the `PrivateRoomScreen` menu (no ViewModel: it only navigates) moved to `ui/private_room/`. Tests in `test/ui/private_room/`
- [x] `WelcomeScreen` / `LoginScreen` / `RegistrationScreen`: `WelcomeViewModel` (`signInWithGoogle`, false when the picker is dismissed), `LoginViewModel` (`login`), `RegistrationViewModel` (`register`); moved to `ui/auth/`. Tests in `test/ui/auth/`
- [x] `StoryReadScreen`: `StoryReadViewModel` (`loadNicknames` started on creation, never fails; `authorNameOf(part)` = nickname or masked email). The screen takes the story and creates the ViewModel in `initState`; `CompleteStoriesScreen` lost its `profileRepository` pass-through (its test provides the repository instead). Moved to `ui/story_read/`; its test moved to `test/ui/story_read/`, gates the lookup explicitly to check the masked-first render, and checks an app rebuild doesn't reload the nicknames
- [x] `HomeScreen` + `RoomRepository`: `RoomRepository` (ChangeNotifier) + `RoomRepositoryLocal` own the language room (via `LanguageRoomPreference`, moved to `data/services/`), how it was picked, and the in-memory private room, which they leave on sign-out (before, Home's state was simply destroyed). `RoomLanguageSource` moved to `domain/models/story_language.dart`. `HomeViewModel` loads the room and exposes it to Home; the selected tab stays in the View. `AccountScreen` reads and changes the room through the repository: its five room parameters and Home's callbacks are gone. `FakeRoomRepository` in `testing/fakes/`; tests in `test/room_repository_local_test.dart` and `test/ui/home/`
- [x] `CompleteStoriesScreen` + `AgeGate` use case: `AgeGate` moved to `domain/use_cases/` (name kept, the age-signals docs use it). It is one app-wide instance (provided in `config/dependencies.dart`) that now also remembers each user's session verdict (`isSessionAdult`/`isSessionMinor`/`rememberVerdict`, formerly static sets in the screen), writes the birth year (`recordBirthYear`) and forgets everything on sign-out by listening to `AuthRepository`; its signal cache is per instance, no longer static. AccountScreen's sign-out no longer clears anything by hand (account deletion now clears too). `CompleteStoriesViewModel`: one subscription per room, the mature filter and "yours first" split (`sections`), the quiet birth-year read, and unlocking as two commands (`unlock` → open / minor / askBirthYear; `submitBirthYear` after the View shows the age screen; `cancelBirthYear`). Screen and `AgeCheckScreen` moved to `ui/complete_stories/`. `mature_story_lock_test` keeps all its cases, now through providers, with sign-out instead of the static clears; ViewModel tests in `test/ui/complete_stories/`
- [x] `AccountScreen`: `AccountViewModel` (nickname: `loadNickname`/`saveNickname` commands, read-only once set, reload when set meanwhile; room: reads and changes `RoomRepository`; account: `deleteAccount` (reauthenticate then delete, false when the Google picker is dismissed) and `signOut` commands). The 811-line screen is split into `ui/account/widgets/`: `account_screen.dart` (layout, navigation, deletion/sign-out reactions), `nickname_card.dart` (form, confirmation, messages), `room_card.dart`, `delete_account_dialog.dart`. Its test-only parameters (`profileRepository`, `email`, `currentEmail`) are gone; tests provide fakes. `account_screen_test` moved to `test/ui/account/` with every case unchanged, plus ViewModel and deletion/sign-out flow tests. Phase 3 done

Pattern: a screen takes only its inputs (e.g. the story) and **creates its ViewModel once, in `initState`**, with repositories from `context.read`, then disposes it. Never build a ViewModel in a route builder or another widget's `build`: Flutter reruns a route's builder whenever the Navigator's dependencies change (`Navigator.didChangeDependencies` → `changedExternalState` → the page is rebuilt), which would create a new ViewModel each time, repeating its side effects (lock, loads) and leaking the old one. Tabs forward input changes (e.g. the room) from `didUpdateWidget`. Tests go in `test/ui/<feature>/`. Per feature: ViewModel unit tests with fakes; update existing widget tests (`account_screen_test`, `mature_story_lock_test`, `story_read_screen_test`) to get dependencies via providers.

### Phase 4: routing (optional, postponed)
- [ ] `go_router` with `redirect` on `AuthRepository`; drop `AuthWrapper`, named routes, `pushNamedAndRemoveUntil` on sign-out/delete. Postponed: navigation works and the app has few routes; worth it with deep links or more screens. Mind the rule in Phase 3: a route builder must not create a ViewModel

### Phase 5: cleanup
- [x] Remove empty `screens/` and `services/`, static `AgeGate` cache (all done during Phase 3)
- [x] Import rules as a test, `test/architecture_test.dart`: `lib/ui` uses no SDK (Firestore, Firebase Auth/Core, Google Sign-In, shared_preferences, age signals), no `data/services` and no repository implementation; `lib/domain` no Flutter, SDK, UI or implementation; `lib/data` never imports `lib/ui`; repository interfaces expose no SDK types. Checked to fail on an injected violation
- [x] `docs/ARCHITECTURE.md` (layers, import rules, ViewModel/View pattern, adding a screen), a new `CLAUDE.md` pointing to it, and the `pr-review` skill's architecture, lifecycle, auth and test sections rewritten for MVVM (the skill lives in the git-ignored `.claude/`, so that change is local)
- [x] Tests left in the root of `test/` moved to mirror `lib/`: `test/data/{repositories,services}/`, `test/domain/{models,use_cases}/`, `test/utils/`, `test/testing/` (the fakes' own test), `test/ui/complete_stories/mature_story_lock_test.dart`; the root keeps only app-level tests (architecture, `AuthWrapper`, smoke)

## Decisions
- **D1 (decided 2026-10-12)** Error handling: keep the existing coded exceptions (`StoryServiceException` etc.). Repositories throw them as today; `Command` catches and exposes the error to the ViewModel/View, which maps the code to l10n. No `Result<T>`.
- **D2 (decided 2026-10-12)** Domain layer only for the age check: `AgeGate` becomes the use case (name kept); other ViewModels call repositories directly, as the guide allows for simple logic.
- **D3 (proposed)** Finish the in-flight branches touching `complete_stories` and `account` (AdMob, mature stories) before Phase 3 reaches those screens.

## Progress log
- 2026-10-12: architecture analysis and roadmap written (this file). D1 decided: keep coded exceptions.
- 2026-10-12: Phase 0 on `feature/mvvm-migration`: `provider` added, `Command` utility, shared UI moved to `lib/ui/core/`. No behaviour change; analyze clean, all tests green. D2 still to decide.
- 2026-10-12: Phase 1, step 1: models moved to `lib/domain/models/` and made pure Dart (no Firestore, no Flutter). No behaviour change; analyze clean, all tests green.
- 2026-10-12: Phase 1, step 2: repositories (abstract + Firestore), domain errors/rules, fakes. No behaviour change; analyze clean, all tests green. Phase 1 done.
- 2026-10-12: Phase 2: `AuthRepository`, providers, screens read dependencies from context. Only intended behaviour difference: during account deletion a `user-not-found` reauth error now shows "invalid credentials" (as login already did) instead of the generic error. Analyze clean, all tests green; sign-in flows not yet verified on a device.
- 2026-10-12: Phase 2 verified on a real device by the owner: email login, registration, Google sign-in, sign-out, account deletion all work.
- 2026-10-12: Phase 3, ChatScreen pilot done. `Command` no longer notifies after dispose. Behaviour change: closing the chat while the lock is still being taken now releases the lock as soon as it lands (before, it stayed held until it expired). Analyze clean, all tests green. Verified on a real device by the owner.
- 2026-10-12: Phase 3, `IncompleteStoriesScreen` done. Only change visible to users: the list no longer resubscribes to Firestore on every rebuild. Analyze clean, all tests green. Verified on a real device by the owner.
- 2026-10-12: Phase 3, private room screens done. No behaviour change. Analyze clean, all tests green. Verified on a real device by the owner.
- 2026-10-12: Phase 3, auth screens done. No behaviour change. Analyze clean, all tests green. Verified on a real device by the owner.
- 2026-10-12: Fix: ViewModels were built in route builders (chat, private room forms, login, registration), which Flutter can rerun, recreating the ViewModel; noticed as nicknames flickering on the story-read screen during its migration. Screens now create their ViewModel in `initState`. Regression test in `test/ui/chat/chat_screen_test.dart`. Verified on a real device by the owner.
- 2026-10-12: Phase 3, `StoryReadScreen` done. No behaviour change: authors still show masked until nicknames arrive, as before. Analyze clean, all tests green. Verified on a real device by the owner.
- 2026-10-12: Phase 3, `HomeScreen` + `RoomRepository` done. Behaviour: the language room is resolved once per app run instead of each time Home is created (same result unless the device language changes while the app runs); the private room is still left on sign-out. Analyze clean, all tests green. Verified on a real device by the owner.
- 2026-10-12: D2 decided. Phase 3, `CompleteStoriesScreen` + `AgeGate` use case done. Behaviour: the session's age verdicts are now also forgotten when the account is deleted (before, only on the sign-out button). Analyze clean, all tests green. Verified on a real device by the owner.
- 2026-10-13: Phase 3, `AccountScreen` done; Phase 3 complete, `lib/screens/` gone. Behaviour: the sign-out button is disabled while signing out, and a sign-out failure shows the generic error (before, it was an unhandled error). Analyze clean, all tests green. Verified on a real device by the owner.
- 2026-10-13: Phase 5 done: architecture test, `docs/ARCHITECTURE.md`, `CLAUDE.md`, `pr-review` skill updated, tests reorganised. No app code changed. Analyze clean, all tests green. Phase 4 postponed.
