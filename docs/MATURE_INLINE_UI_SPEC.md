# Mature stories inline: UI/UX spec

Status: ready to build. Branch: `feature/mature-stories`.
Replaces the "Storie per adulti" entry and its separate list
(`_MatureStoriesEntry` in `lib/screens/complete_stories_screen.dart`).

Wireframe: `docs/mature_inline_wireframe.svg`.

## 1. Goal

Stories with `mature == true` no longer live in a separate section. They show
up in the normal completed-stories list, in the same order as the other
stories, but **locked**. Tapping a locked story runs the existing age gate
(`AgeGate.resolve` → platform signals → `AgeCheckScreen` as a fallback). An
adult goes straight into the story. A minor stays out.

Out of scope: the incomplete-stories list, `StoryReadScreen`, the gate logic
in `AgeGate`/`AgeCheckService` (reused as-is), and the Cloud Functions.

## 2. List composition

| Rule | Detail |
|---|---|
| Included | Completed stories with `mature == false` **or** `mature == true`. Stories still waiting for review (`mature == null`) stay hidden, same as today. |
| Removed | The `matureStoriesEntry` list marker, the entry card under the empty state, and the pushed `Scaffold` titled `matureStoriesTitle`. The `mature` constructor parameter of `CompleteStoriesScreen` goes away. |
| Grouping | Unchanged: the "Le tue storie" heading with the user's stories first, then the divider, then everyone else's. A mature story goes into whichever group it belongs to, even if the user wrote part of it. |
| Order | Chronological inside each group: **newest first**, by completion time (the `timestamp` of the story's last part). Mature and non-mature stories are mixed together. Note: today the list has no explicit order (Firestore returns it in document order), so this sort is new and applies to every story. See open question Q1. |
| Empty state | `noCompleteStories` only shows when there are no completed stories at all, mature ones included. Nothing appears below it. |

Data note for the developer (not UI): the stream must return both values,
e.g. `where('mature', whereIn: [false, true])`. Check the composite index in
`firestore.indexes.json`. The content of mature stories now reaches every
device. It is hidden by the UI only, which matches the client-side-only gate
we already have. The "Known gaps" list still applies.

## 3. Story tile: three visual states

All three states use the existing tile: `CreamCard` > `ListTile`,
`contentPadding: h16 v8`, vertical spacing `4`, `iconColor: AppColors.primary`,
`textColor: AppColors.ink`. Height, padding, radius and elevation are the same
in every state, so locked and unlocked tiles line up exactly.

### 3.1 Normal (`mature == false`), unchanged

- leading: `Icons.menu_book`, 24dp, `AppColors.primary`
- title: `story.title ?? preview`, w600, max 2 lines, ellipsis
- subtitle: `authorsCount(n)`
- trailing: none
- tap: push `StoryReadScreen`

### 3.2 Locked (`mature == true`, session not unlocked)

| Slot | Spec |
|---|---|
| leading | `Icons.lock` (filled), 24dp, colour **`AppColors.primaryDark`** (#3F5A3A, about 6.6:1 on cream). The padlock takes the place of the book icon, in the same slot and at the same size, so the list keeps one column of icons. |
| title | **Do not show the AI title or the first-part preview.** Either one can contain the content the review flagged, and the audience includes children. Show the fixed string `matureStoryLockedTitle` ("Storia per adulti"), w600, `AppColors.ink`, 1 line. |
| subtitle | `authorsCount(n)`, same as a normal tile. This is harmless and keeps the rhythm of the list. |
| trailing | Empty when idle. While the gate is running for this tile: an 18x18 `CircularProgressIndicator(strokeWidth: 2)`, the same spinner the old entry used. |
| dimming / blur | **None.** There is nothing to blur because the real title is never rendered, and lowering opacity would push the text below AA contrast. The padlock and the generic title are enough to tell the tile apart. |
| tap | Starts the gate flow (section 4). |

### 3.3 Unlocked (`mature == true`, user verified adult this session)

- leading: `Icons.menu_book`, same as a normal tile
- title: the real `story.title ?? preview`
- subtitle: `authorsCount(n)`
- trailing: `Icons.lock_open`, **20dp**, `AppColors.primary` (a quiet reminder that the story is for adults, not a call to action). `semanticLabel: matureStoryAdultContent`.
- tap: push `StoryReadScreen` directly, with no gate call.

## 4. Tap flow on a locked tile

```
tap locked tile
  ├─ another gate check is running on this screen → ignore the tap
  ├─ no signed-in email → ignore (same as today)
  ├─ user is a known minor (session set or stored minor year) → snackbar matureStoryUnavailable, stop (no gate, no system sheet)
  │     [superseded 2026-10-22: a known minor's tile is disabled, so this tap can't happen; see PART_MODERATION_PLAN.md D4b]
  └─ show spinner in this tile's trailing slot, call AgeGate.resolve(email)
       ├─ adult        → mark session unlocked → push StoryReadScreen(story)
       ├─ minor        → add to session minors → snackbar matureStoryUnavailable
       ├─ askBirthYear → push AgeCheckScreen (unchanged)
       │     ├─ back without answering (null) → nothing happens: no snackbar, tile stays locked
       │     └─ year chosen → setBirthYear → isAdult?
       │           ├─ yes → AgeCheckScreen is already popped → mark unlocked → push StoryReadScreen(story)
       │           └─ no  → session minor → snackbar matureStoryUnavailable
       └─ exception    → snackbar genericError, tile stays locked
  finally: remove spinner
```

Rules:
- **Open the story directly** after a successful check. Do not go back to the list first and do not show an intermediate screen. Pressing back from the story returns to the list, where the tiles are now unlocked.
- **Only one check at a time per screen.** While one runs, taps on any other locked tile do nothing. Normal and unlocked tiles still work.
- The minor snackbar uses the default `SnackBar` with the text alone: no action and no explanation of the age rule. This keeps the neutral-age-screen principle.
- `AgeCheckScreen` is reused unchanged: its copy, its neutral wording and its write-once note all stay.

## 5. Session unlock and persistence

- After a verdict of **adult** (from signals, a stored year or a freshly entered year), **every** mature tile switches to the Unlocked state (3.3) right away, for the rest of the app session. Keep this in a static set keyed by `UserProfileService.profileKey(email)`, the same pattern as `_sessionMinors`, so the state survives stream rebuilds and leaving and reopening the screen.
- **New app session:** tiles start Locked again. The first tap calls `resolve` again. For a user with a stored adult year this is usually instant, with at most one system sheet that the `AgeGate` session cache then remembers. We do not read anything at `initState` to pre-unlock tiles. A stored adult year is not sufficient on its own because a minor signal must still be able to override it, and the signal check may show UI, so it only runs on a tap.
- > **Superseded (2026-10-22, owner decision):** known minors see mature tiles as locked and **disabled**: padlock, title, subtitle `matureStoryUnavailableLabel` ("Non disponibile") · authors, no tap action, `AgeGate` never called. While the stored-year read runs, the tiles show as normal locked tiles; they are no longer hidden. After a minor verdict from a tap, the snackbar shows once and the tiles turn disabled instead of disappearing. The same applies to the incomplete list. See `docs/PART_MODERATION_PLAN.md` D4b. Original rule, kept for history:
- **Known minor** (in the session set, or a stored year that is not adult, which the screen reads quietly at init through `AgeGate.storedBirthYear`): mature tiles are hidden from the list (user decision, overriding Q2). Mature tiles also stay hidden until the stored-year read finishes, so a known minor never sees one even for a frame. A minor verdict from a tap shows `matureStoryUnavailable` once, then hides the tiles for the session.
- The session-unlocked and session-minor sets must be cleared on sign-out. `clearSessionState()` clears both; sign-out calls it together with `AgeGate.clearSessionCache()`.

## 6. Accessibility

| Item | Requirement |
|---|---|
| Tile semantics | `ListTile` already merges its children. For a **locked** tile, wrap it in `Semantics(button: true, onTapHint: l10n.matureStoryUnlockHint)`. The `Icons.lock` gets `semanticLabel: l10n.matureStoryLockedLabel`. TalkBack/VoiceOver reads: "Storia per adulti, 4 autori, bloccata. Tocca due volte per sbloccare." |
| Unlocked tile | Trailing `lock_open` has `semanticLabel: matureStoryAdultContent`. Read as "<title>, 4 autori, contenuto per adulti". |
| Busy state | The spinner needs no label of its own (the repo has no `loading` key, and the platform sheet or the age screen that follows is announced). Do not move focus. |
| Focus after flow | On return from `AgeCheckScreen` or `StoryReadScreen`, focus goes back to the tapped tile (the default route behaviour, so do not override it). Snackbars are announced by the platform. |
| Tap target | The whole tile is the target, at least 56dp high, which ListTile already provides. The padlock is decorative and has no tap handler of its own. |
| Contrast | Ink on cream is about 11.8:1. `primaryDark` padlock on cream is about 6.6:1. `primary` lock_open on cream is about 3.9:1, which passes the 3:1 minimum for non-text graphics. No opacity is applied to locked tiles. |
| Text scaling | Up to 2.0x the locked title wraps to at most 2 lines, like the normal title. The padlock stays at a fixed 24dp. |
| Dark mode | N/A. The app is light-only (`ThemeData.light()` in `main.dart`) and uses fixed `AppColors`. No dark variants are needed. |

## 7. Copy / l10n

Locales in the repo: `lib/l10n/app_it.arb`, `lib/l10n/app_en.arb`.

### Add

| Key | it | en |
|---|---|---|
| `matureStoryLockedTitle` | Storia per adulti | Story for adults |
| `matureStoryLockedLabel` | bloccata | locked |
| `matureStoryUnlockHint` | sbloccare | unlock |
| `matureStoryAdultContent` | contenuto per adulti | adult content |
| `matureStoryUnavailable` | Questa storia non è disponibile. | This story isn't available. |

`matureStoryUnlockHint` is used as `onTapHint`. The platform adds the
"Tocca due volte per…" / "Double tap to…" prefix, so the string is just the
verb. Add `@key` descriptions in `app_it.arb` (the template) that note the
screen-reader context.

### Remove (once nothing references them)

`matureStoriesEntryTitle`, `matureStoriesEntrySubtitle`, `matureStoriesTitle`,
`noMatureStories`, `matureStoriesUnavailable` (replaced by
`matureStoryUnavailable`, because "sezione" no longer makes sense).

### Keep, unchanged

`ageCheckTitle`, `ageCheckQuestion`, `ageCheckHint`, `ageCheckNote`,
`ageCheckConfirm`, `genericError`, `authorsCount`, `noCompleteStories`,
`yourStoriesHeading`.

Regenerate `app_localizations*.dart` with `flutter gen-l10n`. Do not edit them
by hand.

## 8. Edge cases

- **A story becomes mature while the list is open** (the review lands live): the tile turns Locked in place, or Unlocked if the session is already unlocked. If that story is currently open in `StoryReadScreen`, leave it open; it is not kicked out.
- **A mature story the user co-wrote:** still locked. The user already knows their own part but not the rest.
- **Rapid double tap on a locked tile:** the second tap is ignored by the in-flight guard, so only one `AgeCheckScreen` gets pushed.
- **The screen is disposed during the check** (the user switches tab): no navigation, no snackbar (`mounted` checks). The verdict is still cached by `AgeGate` and the session sets.
- **Private rooms:** same behaviour. The session unlock applies across rooms.
- **Gate timeout** (`AgeGate.defaultTimeout`, 20s): the spinner shows the whole time, then the flow falls back to `AgeCheckScreen` as today.

## 9. Acceptance criteria

1. The "Storie per adulti" entry card is gone from the list and from the empty state. No route pushes a mature-only list.
2. Mature and non-mature completed stories appear in one list, keeping the "Le tue storie" / divider grouping, with each group sorted newest-first by completion time. Unreviewed stories (`mature == null`) do not appear.
3. A locked tile has the same size as a normal tile, shows a filled 24dp `Icons.lock` in `AppColors.primaryDark` in the leading slot, the title "Storia per adulti" / "Story for adults", the subtitle `authorsCount`, and **never** renders `story.title` or any part text. A widget test asserts the real title is not found.
4. Tapping a locked tile while no verdict is known calls `AgeGate.resolve` once and shows an 18dp spinner in that tile's trailing slot until it finishes.
5. Adult verdict (signals, stored year or new year) → `StoryReadScreen` for **that** story opens directly. When the user comes back, every mature tile is in the Unlocked state (real title, book icon, 20dp `lock_open` trailing).
6. Unlocked state lasts for the app session and survives stream updates and reopening the screen. It resets on a cold start and on sign-out.
7. Minor verdict, or a minor year entered → snackbar "Questa storia non è disponibile." The tile stays locked, and later taps show the same snackbar with no gate call and no `AgeCheckScreen`.
8. Back from `AgeCheckScreen` without confirming → no snackbar, no stored year, the tile stays locked.
9. A gate exception → `genericError` snackbar, the tile stays locked, and the spinner is removed.
10. While a check runs, taps on other locked tiles are ignored. Normal and unlocked tiles still open.
11. Screen reader on a locked tile announces the generic title, the author count, "bloccata"/"locked", and the hint "sbloccare"/"unlock". On an unlocked tile it announces "contenuto per adulti"/"adult content".
12. The ARB files contain the five new keys in it and en, and the five old keys are removed. `flutter gen-l10n` and `flutter analyze` are clean.

## 10. Open product questions (non-blocking; defaults above)

- **Q1 Order.** Default: newest-first by completion time, within the existing "mine / others" groups. Confirm the direction, and confirm the grouping should stay.
- **Q2 Known minors.** Default: they see locked tiles, and a tap gives "non disponibile". Alternative: hide mature tiles entirely from known minors, as the old entry did. That is safer for kids, but it means the requirement "appear with a padlock" only applies to users whose age is unknown or adult.
- **Q3 Locked title.** Default: a generic "Storia per adulti" with the AI title hidden. If you would rather show the AI title, the review prompt must guarantee titles are child-safe first.
