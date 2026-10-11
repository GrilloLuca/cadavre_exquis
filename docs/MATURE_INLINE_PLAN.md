# Mature stories inline, with a padlock (replaces the "Storie per adulti" section)

Status: proposed (2026-10-11), branch `feature/mature-stories`. Builds on c91c047 (AI `mature` flag, separate section) and 9b321c4 (`AgeGate`, see `docs/AGE_SIGNALS_PLAN.md`).

## Requirement
- Remove the "Storie per adulti" section.
- Stories with `mature == true` appear in the complete stories list together with the others, in chronological order, with a padlock.
- Tapping a locked story runs the existing age flow (`AgeGate.resolve`: platform signals first, then the birth-year screen). After an adult verdict the story opens.

## Current state (facts from the code)
- `StoryService.completeStoriesStream({language, roomId, mature = false})` filters with `where('mature', isEqualTo: mature)`. Unreviewed stories (no `mature` field) are in neither list.
- There is no ordering at all: no `orderBy` in the query and no client sort, so the list follows document-id order (effectively random). "Chronological" is new behaviour, not a preserved one.
- `CompleteStoriesScreen` has a `mature` flag and is pushed a second time, wrapped in a Scaffold, as the mature list. `_MatureStoriesEntry` holds the gate flow: quiet `storedBirthYear` read in `initState` (to hide the entry from known minors), `resolve` on tap, `AgeCheckScreen` on `askBirthYear`, a static `_sessionMinors` set, a spinner and double-tap guard, `genericError` snackbar on failure.
- `AgeGate` caches definitive signals per user in a static map for the session; it never writes signals. Stored birth year is write-once (`ageChecks/{emailKey}`).
- The only path to `StoryReadScreen` is `CompleteStoriesScreen._buildStoryCard`. `home_screen.dart` builds `CompleteStoriesScreen` without `mature`.
- Rules: `stories` are readable by any signed-in user; the age gate is app-side only (unchanged by this plan).

## Decisions

### D1. Query: `mature in [false, true]` (keep unreviewed stories hidden)
`completeStoriesStream` drops the `mature` parameter and uses `where('mature', whereIn: [false, true])`.
- Unreviewed stories stay hidden: they could be mature and there is nothing to put a padlock on yet. The review runs seconds after completion, and `functions/scripts/review-complete-stories.js` covers failures.
- `in` is served like equality, so the existing composite indexes `(status, language, roomId, mature)` and `(status, roomId, mature)` cover it. No index change. The two older indexes without `mature` are unused by the app already; leave them (removing indexes is out of scope and harmless to keep).
- Rejected: `isNotEqualTo: null` (forces an inequality orderBy on `mature` and a new index); dropping the filter (shows unreviewed stories unlocked).

### D2. Chronological order: client-side, newest completed first
Sort in the service (or a pure helper next to it) by the completion time = timestamp of the last part (`parts.last.timestamp`), descending, ties by id.
- Every complete story has parts with a timestamp, including stories from older app versions; `updatedAt`/`createdAt` aren't in the model and may be missing on legacy docs, and a Firestore `orderBy` on a missing field would silently drop those docs and need new indexes.
- Lists are small (one room's completed stories), so client sorting is free.
- The existing "Your stories" heading + divider split stays; each group is sorted. Mature stories go into whichever group they belong to.
- Assumption to confirm with Luca: newest first. (Oldest first is a one-line change.)

### D3. Locked row content: no title, no preview
A locked row shows a neutral label ("Storia per adulti" / "Story for adults"), the authors count and a padlock (`Icons.lock`, leading, replacing `menu_book`). The AI title is not shown until the user is verified adult.
- The title is generated from the story text and can itself be explicit; the preview (first part) certainly can. Showing either defeats the gate.
- Trade-off: rows are less inviting and indistinguishable from each other. Acceptable; once verified (D4) titles appear.

### D4. Verified adults: unlock for the session, re-resolve on next launch
- After an `adult` outcome (verdict, or birth year from `AgeCheckScreen` that `isAdult`), mark the user unlocked in a static session set (same pattern as `_sessionMinors`). All mature rows then show their title, a `lock_open` icon (or the normal `menu_book`, frontend's choice, consistent across rows), and open directly with no gate call.
- On the next app launch the first tap calls `resolve` again. With a stored adult year and no signal this is instant with no UI; with a cached/permanent "unavailable" signal it shows no sheet; on iOS 26+ with Declared Age Range a sheet can appear once per launch (already accepted in AGE_SIGNALS_PLAN).
- Rejected: proactively unlocking from a stored adult year in `initState`. A minor platform signal must be able to override a stored adult year, and signals may only be requested on tap.

### D5. Minors: snackbar, then hide mature rows for the session
Reuse the current behaviour, applied to rows instead of the entry:
- Known minor (stored minor birth year, read quietly in `initState`, or the session minors set): mature rows are filtered out of the list entirely. If nothing remains, show the normal `noCompleteStories` empty state.
- Unknown user who taps and gets `minor` (signal or birth-year answer): snackbar "This story isn't available." and all mature rows disappear for the session.
- Cancelling the birth-year screen (pop with null): nothing happens, row stays locked.
- Trade-off: a known minor doesn't see that locked stories exist, which matches the previous "minors don't see the section at all" behaviour and the README; the requirement's padlock applies to users whose age is unknown or adult.

### D6. Backend: no functional change
- `reviewCompletedStory`, `saveReview`, the backfill script, rules and indexes stay functionally as they are. Only stale comments change (index.ts doc comment around line 153, rules comment above `allow read`, README).
- Known, pre-existing limitation made more visible: mature story documents are now streamed to every device (before, only after the gate opened the second list). Rules always allowed this; the gate is a UX/age-appropriateness control, not access control. See Risks.

## Files to change
| File | Change |
|---|---|
| `lib/services/story_service.dart` | `completeStoriesStream`: drop `mature` param, `whereIn: [false, true]`, sort per D2 |
| `lib/screens/complete_stories_screen.dart` | Remove `mature` flag, `_ListMarker.matureStoriesEntry`, `_MatureStoriesEntry`, the nested mature screen; add locked row + gate flow per story; known-minor filtering |
| `lib/l10n/app_it.arb`, `lib/l10n/app_en.arb` + regenerated `app_localizations*.dart` | Remove `matureStoriesEntryTitle`, `matureStoriesEntrySubtitle`, `matureStoriesTitle`, `noMatureStories`, `matureStoriesUnavailable`; add `matureStoryLockedTitle`, `matureStoryLockedLabel`, `matureStoryUnlockHint`, `matureStoryAdultContent`, `matureStoryUnavailable` |
| `test/story_service_test.dart` | Rewrite the mature test; add ordering test |
| `test/mature_stories_entry_test.dart` | Replace with `test/mature_story_lock_test.dart` |
| `firestore.rules` | Comment only (above `allow read` in `stories`) |
| `functions/src/index.ts` | Comment only (`reviewCompletedStory` doc comment) |
| `README.md` | Moderation paragraph and the `complete_stories_screen.dart` tree note |
| `pubspec.yaml` | Version bump at release |
| `lib/screens/account_screen.dart` | Sign-out clears `CompleteStoriesScreen` session state and `AgeGate.clearSessionCache()` |
| `lib/services/age_gate.dart`, `lib/services/age_signals_source.dart` | Comments only; `clearSessionCache` is no longer `@visibleForTesting` |
| Unchanged | `age_check_service.dart`, `age_check_screen.dart`, `story_read_screen.dart`, `firestore.indexes.json`, `home_screen.dart` (no `mature` arg passed) |

## Tasks

### B1 (backend-developer): data layer, about 2h
- `StoryService.completeStoriesStream({required language, String? roomId})`: remove `mature`; filter `mature` with `whereIn: [false, true]`; return stories sorted by last-part timestamp descending, ties by id ascending. Put the comparator in a pure, testable function (e.g. `Story.completedAt` getter returning `parts.last.timestamp` or null, plus a static comparator); stories with no parts sort last.
- Update the doc comments in `story_service.dart`, the `stories` rules comment in `firestore.rules`, and the `reviewCompletedStory` doc comment in `functions/src/index.ts` (comment-only edits; no deploy needed for rules or functions, but deploying the rules comment is harmless).
- `test/story_service_test.dart`: replace "mature stories are only in the mature list..." with "complete list includes reviewed mature and non-mature stories, excludes unreviewed"; add an ordering test with three stories whose last parts have different timestamps, plus one tie.
- Acceptance criteria:
  - One stream returns `mature: false` and `mature: true` stories of the room; a complete story without `mature` is excluded; room/language filtering tests still pass unchanged.
  - Order is newest last-part first, deterministic on ties.
  - `firestore.indexes.json` unchanged; verify once against the real project (or emulator) that the `in` query on both public and private rooms runs without a missing-index error.
  - `flutter analyze` clean, `flutter test test/story_service_test.dart` passes.
  - If `fake_cloud_firestore` doesn't combine `whereIn` with `isNull` correctly, report it rather than changing the query shape.

### F1 (frontend-developer): inline locked rows and tap flow, about 5h (after B1)
- `complete_stories_screen.dart`:
  - Remove the `mature` constructor param, `_ListMarker.matureStoriesEntry`, `_matureStoriesEntry()`, `_MatureStoriesEntry` and the nested mature `Scaffold`. Keep the injectable `storyService`, `ageGate`, `ageCheckService`, `email`.
  - Convert to a StatefulWidget (or extract a stateful list body) that owns: the quiet stored-birth-year read in `initState` (via `AgeGate.storedBirthYear`), the static session sets `_sessionMinors` and `_sessionAdults` keyed by `UserProfileService.profileKey(email)`, and the id of the story whose check is running (`_checkingStoryId`, null when idle).
  - Rendering: `mature != true` rows unchanged. `mature == true` rows: if known minor, filtered out before the mine/others split; if session adult, normal row with title (icon per D4); otherwise locked row per D3 with `Icons.lock` (semantics label `matureStoryLockedLabel`) and the tap hint `matureStoryUnlockHint`; unlocked mature rows show a trailing `Icons.lock_open` labelled `matureStoryAdultContent`. Until the quiet birth-year read has finished, mature rows are hidden, so a known minor never sees a locked tile flash in.
  - Tap on a locked row: same logic as today's `_open` (resolve, `AgeCheckScreen` on `askBirthYear`, `setBirthYear`, `isAdult`, `genericError` on exception), but on adult add to `_sessionAdults`, `setState`, then push `StoryReadScreen` for that story; on minor add to `_sessionMinors`, `setState`, snackbar `matureStoryUnavailable`. While a check runs the tapped row shows a small spinner in `trailing` and taps on any locked row are ignored.
  - Empty state: `noCompleteStories` when the filtered list is empty; no mature entry below it.
  - `clearSessionState()` clears both sets; sign-out (`account_screen.dart`) calls it together with `AgeGate.clearSessionCache()`.
- l10n (both ARBs, Italian is the template): remove the five keys listed above; add
  - `matureStoryLockedTitle`: "Storia per adulti" / "Story for adults"
  - `matureStoryLockedLabel` (padlock semantics label): "bloccata" / "locked"
  - `matureStoryUnlockHint` (tap hint verb): "sbloccare" / "unlock"
  - `matureStoryAdultContent` (open-padlock semantics label): "contenuto per adulti" / "adult content"
  - `matureStoryUnavailable`: "Questa storia non è disponibile." / "This story isn't available."
  Run `flutter gen-l10n` and commit the generated files. Confirm with `grep` that no removed key is referenced.
- Tests: delete `test/mature_stories_entry_test.dart`, add `test/mature_story_lock_test.dart` reusing its fakes (`_FakeSource`, `FakeFirebaseFirestore`, seeded birth year). Seed one normal and one mature story.
- Acceptance criteria (each a widget test):
  1. Mature and normal stories appear in one list, in the service's order; the mature row shows `matureStoryLockedTitle`, a lock icon, and neither its AI title nor its first part.
  2. No "Stories for adults" entry and no nested list exist anywhere.
  3. Adult signal: tap opens `StoryReadScreen` for that story, no `AgeCheckScreen`, nothing written to `ageChecks`, source called once.
  4. After 3, the mature row shows its title; tapping it (and another mature row) opens directly, source still called once, also after the list is rebuilt.
  5. Unavailable signal, no stored year: `AgeCheckScreen` shown; adult year stored and story opens; minor year stored, snackbar `matureStoryUnavailable`, mature rows gone.
  6. Cancel on `AgeCheckScreen`: nothing stored, row still locked, no snackbar.
  7. Minor signal: snackbar, mature rows gone, normal rows still there; still gone after rebuild in the same session.
  8. Stored minor year: mature rows never rendered and the source is never called; if the only story is mature, `noCompleteStories` is shown.
  9. Stored adult year + unavailable signal: tap opens the story without `AgeCheckScreen`.
  10. Pending check: spinner on the tapped row, second tap ignored (source called once), story opens when the signal completes.
  11. A mature story the user co-wrote is under "Your stories", still locked.
  - `flutter analyze` clean; full `flutter test` passes.

### D1 (Luca or either developer): docs and release, about 30 min
- README: moderation paragraph ("flagged stories stay in the list with a padlock; opening one requires the age check; under-18s don't see them") and the tree note for `complete_stories_screen.dart`.
- Update the memory note / `docs/AGE_SIGNALS_PLAN.md` header to point at this plan for the UI part.
- Bump `pubspec.yaml` version. No Firestore or Functions deploy required (comment-only changes). Release order is unconstrained because the backfill already ran for 1.0.9.

## Risks
1. **Mature content reaches every device.** Full documents of mature stories are now streamed to all users, including minors, and cached by Firestore offline persistence. A modified client or a debugger can read them. This was already possible (rules allow reading any story); the gate stays a UX control. If real access control is wanted later: move the text to a subcollection readable only via a callable that checks age, which is a larger change (not in scope).
2. **Title leak via other surfaces.** The title is hidden in the list only. `StoryReadScreen` shows it after unlock, which is fine. Any future surface (notifications, share, home preview) must check `mature` too.
3. **Ordering assumption.** "Chronological" interpreted as newest completed first by last-part timestamp. Part timestamps are client-generated (`Timestamp.now()`), so clock skew on a device can misplace a story slightly. Acceptable; a server `completedAt` would need a rules + function change.
4. **Unreviewed window.** A just-completed story is invisible for a few seconds until the review lands, and indefinitely if the review fails (until the backfill script is run). Unchanged from today; consider a log-based alert on "Story review failed".
5. **Repeated system sheet.** Each launch, the first locked tap may trigger Apple's/Play's sheet (where available). Already accepted; mitigated by the existing session and "permanently unavailable" caches.
6. **Known-minor UX.** Hiding rows (D5) means a minor sees fewer stories without explanation. If product prefers showing locked rows to minors too, it's a one-condition change in F1 (keep the row, show the snackbar on tap without calling the gate).
7. **`fake_cloud_firestore` fidelity** for `whereIn` + `isNull`: tests could pass while production needs an index (or vice versa). Mitigated by the one-off real query check in B1.

## Open questions (non-blocking; defaults above)
- Newest first or oldest first? (Default: newest first.)
- Should known minors see locked rows at all? (Default: no, D5.)
