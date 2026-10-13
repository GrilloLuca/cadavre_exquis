# Cadavre Exquisite (Flutter + Firebase)

A turn-based collaborative writing game: four players write the four parts of a story, each seeing only the last five words of the previous part.

## Commands

```sh
flutter pub get
flutter analyze
flutter test        # includes test/architecture_test.dart (layering rules)
flutter gen-l10n    # after editing lib/l10n/app_it.arb / app_en.arb
```

CI (`.github/workflows/ci.yml`) runs analyze + test on every PR; see `docs/CI_CD.md` for deploys.

## Architecture

MVVM as in the official Flutter guide. Read `docs/ARCHITECTURE.md` before adding or changing a screen. The essentials:

- `lib/data` (repositories behind interfaces, SDK wrappers), `lib/domain` (plain models, coded exceptions, the `AgeGate` use case), `lib/ui/<feature>/{view_models,widgets}`, `lib/config/dependencies.dart` (providers).
- The UI never uses Firebase/Google/shared_preferences or repository implementations directly; `test/architecture_test.dart` fails if it does.
- A screen creates its ViewModel once, in `initState`, from `context.read`, and disposes it. Never build a ViewModel in a route builder or another widget's `build`.
- ViewModel actions are `Command`s (`lib/utils/command.dart`); repositories throw coded exceptions that the View maps to l10n strings.
- Tests mirror `lib/` under `test/`; ViewModel and widget tests use the in-memory fakes in `testing/fakes/repositories/`.

## Conventions

- User-visible text only through `AppLocalizations`; Italian (`app_it.arb`) is the template, English must be updated too.
- Firestore read-modify-write on stories and rooms goes through transactions; legacy documents may lack newer fields.
- Commits: use the `commit-message` skill (it bumps the patch version in `pubspec.yaml` every commit). The owner checks each change on a real device before committing; don't push.
- `docs/` holds the plans and specs of past features; `docs/MVVM_MIGRATION.md` records how the architecture got here.
