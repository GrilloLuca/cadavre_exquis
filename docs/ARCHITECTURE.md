# Architecture

The app follows the MVVM architecture of the official Flutter guide (https://docs.flutter.dev/app-architecture/guide). How it got here, step by step, is in `docs/MVVM_MIGRATION.md`; this file is the short version for writing new code.

`test/architecture_test.dart` enforces the import rules below: a violation fails `flutter test` with the file and the import.

## Layers

```
lib/
  main.dart            Firebase init, providers, routes, AuthWrapper
  config/              dependencies.dart: the app's providers
  data/
    repositories/<x>/  <x>_repository.dart (interface) + <x>_repository_firestore|firebase|local.dart
    services/          thin wrappers over SDKs/plugins (Google Sign-In, age signals, FCM, shared preferences)
  domain/
    models/            plain Dart: Story, PrivateRoom, Nickname, AgeRules, coded exceptions...
    use_cases/         AgeGate (the only use case, decision D2)
  ui/
    core/              theme, shared widgets, positionLabel, view_models/ (MatureStoryAccess: the mature-story gate shared by the story lists and the notification router)
    <feature>/view_models/  one ViewModel per screen
    <feature>/widgets/      the screen and its pieces
  utils/               Command
testing/fakes/         in-memory repositories for tests
test/                  mirrors lib/ (data/, domain/, ui/<feature>/, utils/)
```

| Layer | May import | Must not import |
|---|---|---|
| `ui` | `domain`, repository **interfaces**, `domain/use_cases`, `utils`, Flutter, `provider` | Firebase / Google / shared_preferences SDKs, `data/services`, repository implementations |
| `domain` | other `domain`, repository interfaces, `data/services/age_signals_source.dart` | Flutter, SDKs, `ui`, implementations |
| `data` | `domain`, SDKs | `ui` |
| repository interfaces | `domain`, `flutter/foundation.dart` (ChangeNotifier) | SDK types |

Only `config/` creates repository implementations (`dependencies.dart`, plus `ads_repository_factory*.dart`, a conditional import that keeps `google_mobile_ads` out of the web build).

One exception to the UI rule: `ui/core/ui/ad_banner_view.dart` may use `google_mobile_ads`, because a banner ad is a native view drawn by the SDK's widget. It only loads and shows the ad unit that `AdBanner` gets from `AdsRepository`; the test names the file, so the allowance can't spread.

## Repositories

- Source of truth for one kind of data, behind an abstract class. The UI only knows the interface.
- Errors are **coded exceptions** from `domain/models` (`StoryException`, `PrivateRoomException`, `UserProfileException`, `AuthException`), never user-facing text (decision D1). The View maps the code to an `AppLocalizations` string.
- Firestore documents are converted to domain models inside the data layer (e.g. `story_firestore_mapping.dart`); domain models carry `DateTime`, never `Timestamp`.
- Repositories with state the UI follows (`AuthRepository`, `RoomRepository`, `NotificationRepository`) extend `ChangeNotifier`. `RoomRepository` and `AgeGate` forget session state on sign-out by listening to `AuthRepository`; `NotificationRepository` registers the device on sign-in the same way, but must be unregistered *before* sign-out (`AccountViewModel.signOut`), while the user can still delete its token.

## ViewModels and Views

- A ViewModel extends `ChangeNotifier`, takes repositories (and `AgeGate`) in its constructor, exposes state as getters and actions as `Command`s (`lib/utils/command.dart`). It never touches `BuildContext`, navigation or l10n.
- `Command0`/`Command1` run an async action and expose `running`, `error`, `value`, `completed`. They catch exceptions (D1), ignore calls while running (no double submit) and don't notify after dispose.
- The View (a `StatefulWidget`) **creates its ViewModel once, in `initState`**, from `context.read`, and disposes it in `dispose`. It takes only its inputs (e.g. the story, the room) as constructor parameters.
  - Never build a ViewModel in a route builder or another widget's `build`: Flutter reruns a route's builder whenever the Navigator's dependencies change, which recreates the ViewModel, repeats its side effects (locks, loads) and leaks the old one. `test/ui/chat/chat_screen_test.dart` and `test/ui/story_read/story_read_screen_test.dart` have regression tests for this.
  - Inputs that change while the screen lives (the room of a Home tab) are forwarded from `didUpdateWidget` (e.g. `setRoom`).
- The View listens to its commands (`addListener` in `initState`, removed in `dispose`) to navigate, show snack bars and map errors, then calls `clearResult()`. It rebuilds with `ListenableBuilder` over the ViewModel and the commands it shows.
- Pure presentation stays in the View: form validation messages, the selected tab, controllers and focus nodes.
- A flow that needs a screen in the middle is split into commands around it (e.g. `CompleteStoriesViewModel.unlock` → age screen → `submitBirthYear` / `cancelBirthYear`).

## Adding a screen

1. Data: extend or add a repository interface + implementation, a fake in `testing/fakes/repositories/`, and provide the implementation in `config/dependencies.dart`.
2. `lib/ui/<feature>/view_models/<feature>_view_model.dart` with its commands.
3. `lib/ui/<feature>/widgets/<feature>_screen.dart` creating the ViewModel in `initState`.
4. Tests in `test/ui/<feature>/`: ViewModel unit tests on the fakes, widget tests with the fakes provided via `provider`.
5. New user-visible text in both `lib/l10n/app_it.arb` and `app_en.arb`, then `flutter gen-l10n`.
