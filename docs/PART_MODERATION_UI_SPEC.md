# Part moderation: UI spec (tiles, chat, notifications)

Status: ready to build (F3, F4, F5, F6, F7 of `docs/PART_MODERATION_PLAN.md`).
Owner confirmed defaults Q1–Q9 on 2026-10-22. Base branch `release/1.1.0`.

This spec supersedes `docs/MATURE_INLINE_UI_SPEC.md` §4 (the known-minor tap
branch) and §5 (known minors hidden). Everything else there still applies: tile
metrics, the gate tap flow, the spinner, session unlock, sign-out reset.

Terms (from the plan): **awaiting review** = `Story.awaitingReview` (D3).
**Known minor** = stored non-adult birth year or session minor verdict.
**Session adult** = adult verdict this session. **Unknown age** = neither,
including "stored-year read not finished yet". `MatureTileState` comes from F2.

## 1. Shared tile anatomy (unchanged)

Every state uses the existing tile: `CreamCard` > `ListTile`,
`contentPadding: h16 v8`, `iconColor: AppColors.primary`,
`textColor: AppColors.ink`, leading icon 24dp. Same height in every state, so
tiles never jump when a state changes live.

| Token | Value | Use |
|---|---|---|
| `AppColors.primary` #5E7F55 | ~3.9:1 on cream | normal leading icons, `lock_open` |
| `AppColors.primaryDark` #3F5A3A | ~6.6:1 on cream | padlock on an **enabled** locked tile |
| `AppColors.ink` #2E2E28 | ~11.8:1 on cream | text on enabled tiles |
| `Theme.disabledColor` (black38) | ~2.6:1 on cream | everything on a **disabled** tile (text, leading icon, keywords line) |

Disabled tiles keep the pattern the incomplete list already uses for
`beingWritten` / `waitingForOthers`: `ListTile.enabled: false`, `onTap: null`,
and the ListTile's own disabled tint. Inactive controls are exempt from WCAG
1.4.3/1.4.11. The reason is always in the subtitle as text, so colour is never
the only cue. **Rule:** on a disabled tile, don't give the leading icon or the
keywords text an explicit colour, so they pick up the disabled tint like the
title. Today the complete list's padlock (`primaryDark`), tag icon and keywords
text set explicit colours; in the unavailable state those must be left unset or
set to `Theme.of(context).disabledColor`.

Give each card a `ValueKey(story.id)`, so a tile that changes state in place
keeps screen-reader focus. State changes are **not** announced (no
`liveRegion`): both lists are live streams, and announcements would be noisy.

## 2. Incomplete list (`IncompleteStoriesScreen`)

### 2.1 Precedence, first match wins

1. `mature == true` and known minor → **unavailable**
2. awaiting review → **in review**
3. lock held by someone else → **being written**; user wrote the last part → **waiting for others**. If `mature == true` and not session adult, the leading icon becomes the padlock.
4. `mature == true` and not session adult → **locked**
5. `mature == true` and session adult → **unlocked**
6. otherwise → **available**

Title in every state: `positionLabel(context, story.currentPosition)`, w600,
1 line. Incomplete stories have no AI title. The last five words appear
**only** in the available and unlocked states.

### 2.2 States

| State | Leading | Subtitle (1 line, ellipsis) | Trailing | Enabled | Tap |
|---|---|---|---|---|---|
| available | `Icons.edit_note` | `"...<lastFiveWords>"`, or `storyNotStarted` with 0 parts | none | yes | push `ChatScreen` |
| unlocked | `Icons.edit_note` | `"...<lastFiveWords>"` | `Icons.lock_open` 20dp, `primary`, `semanticLabel: matureStoryAdultContent` | yes | push `ChatScreen` (no gate) |
| in review | `Icons.hourglass_top` (decorative, no label) | `storyUnderReview` | none | **no** | none |
| being written | `TypingIndicator`, or `Icons.lock` if mature and not session adult | `storyBeingWritten` | none | no | none |
| waiting for others | `Icons.hourglass_empty`, or `Icons.lock` if mature and not session adult | `storyWaitingForOthers` | none | no | none |
| locked | `Icons.lock` 24dp `primaryDark`, `semanticLabel: matureStoryLockedLabel` | `matureStoryLockedTitle` | 18dp spinner (`strokeWidth: 2`) while this tile's check runs, else none | yes | gate flow (2.3) |
| unavailable | `Icons.lock` 24dp, disabled tint, `semanticLabel: matureStoryLockedLabel` | `matureStoryUnavailableLabel` | none | **no** | none, `AgeGate` never called |

On being written / waiting for others the padlock uses the disabled tint and
`semanticLabel: matureStoryLockedLabel`.

### 2.3 Locked tile tap (same flow as the complete list, `MATURE_INLINE_UI_SPEC.md` §4)

- If another check is running on this screen, ignore the tap.
- Otherwise show the spinner in this tile and call the F2 unlock:
  - **adult** → push `ChatScreen(story)` with the latest snapshot. If the story changed meanwhile (taken, or in review), the chat's lock fails and pops with its usual snackbar (§4). Don't pre-check.
  - **minor** → snackbar `matureStoryUnavailable`, shown once. Every mature tile in both lists switches to **unavailable**.
  - **askBirthYear** → `AgeCheckScreen`. Back without answering → nothing happens.
  - **error** → `genericError` snackbar.
- Remove the spinner when the flow ends.

### 2.4 Screen semantics (what a screen reader announces)

| State | Announced (it) | Extra semantics |
|---|---|---|
| available | "Sviluppo (1/2), "...ultime cinque parole"" | button (ListTile default) |
| unlocked | "…, contenuto esplicito" | button |
| in review | "Sviluppo (1/2), In revisione..., disattivato" | none; disabled |
| being written / waiting | as today (+ "bloccata" when padlocked), disabled | none |
| locked | "Sviluppo (1/2), bloccata, Contenuto esplicito. Tocca due volte per sbloccare" | `Semantics(button: true, onTapHint: matureStoryUnlockHint)` |
| unavailable | "Sviluppo (1/2), bloccata, Non disponibile, disattivato" | **no** button / onTapHint wrapper |

### 2.5 Other incomplete-list rules

- **Empty state:** `noIncompleteStories` only when the list has no stories at all. In-review and unavailable tiles count as stories.
- **FAB / `canCreateStory`:** stories with `mature == true` are ignored. A known minor whose own introduction was flagged sees it as unavailable and can still create a story; `newStoryBlocked` doesn't show for it.
- **Before the stored-year read finishes:** mature tiles render as **locked**, never hidden and never unavailable. A tap in that window goes through the normal flow and may end as minor (one snackbar).
- **Live changes:** in review → available / locked / unavailable / unlocked (or waiting for others for the writer who just submitted) without a reload, typically within seconds.

## 3. Complete list (`CompleteStoriesScreen`)

Stories with `reviewedAt == null` are never listed, never counted and never
matched by search. Precedence: unavailable (mature, known minor) > locked
(mature, not session adult) > unlocked (mature, session adult) > normal.

| State | Leading | Title (w600, ≤2 lines) | Subtitle line 1 | Keywords line | Trailing | Enabled | Tap |
|---|---|---|---|---|---|---|---|
| normal | `Icons.menu_book` | `title ?? first part` | `authorsCount(n)` | as today | none | yes | `StoryReadScreen` |
| unlocked | `Icons.menu_book` | `title ?? first part` | `authorsCount(n)` | as today | `lock_open` 20dp, `matureStoryAdultContent` | yes | `StoryReadScreen`, no gate |
| locked (as today) | `Icons.lock` `primaryDark`, `matureStoryLockedLabel` | `title ?? matureStoryLockedTitle` | `matureStoryLockedTitle · authorsCount(n)` when there is a title, else `authorsCount(n)` | as today | spinner while checking | yes | gate flow |
| **unavailable** | `Icons.lock`, disabled tint, `matureStoryLockedLabel` | `title ?? matureStoryLockedTitle` (AI title is child-safe, Q9) | `matureStoryUnavailableLabel · authorsCount(n)` | shown, disabled tint; search matches stay w700 | none | **no** | none, `AgeGate` never called |

The unavailable tile never renders part text: the first-part preview is never
used as a title fallback.

Semantics of the unavailable tile: "<title>, bloccata, Non disponibile · 4
autori, parole chiave: …, disattivato". No `Semantics(button:, onTapHint:)`
wrapper. The locked tile keeps its wrapper.

**Search:** unavailable stories match on AI title and keywords like any other.
The tab counts (`storiesTabCount`) and the no-match cards count them.

**Empty states:** `totalCounts` includes unavailable stories. A room whose only
completed stories are mature shows them to a minor, not `noCompleteStories`.
The opening-tab choice (mine vs others) counts them too. The
`_onViewModelChanged` comment "a minor verdict hides its only stories" no
longer applies. A minor verdict now never empties the list.

## 4. Chat (`ChatScreen`)

- `lockStory` fails with `StoryErrorCode.underReview` → the existing lock-error path: `Navigator.pop`, then a default `SnackBar` (no colour, no action) on the screen below showing `storyUnderReviewError`. The composer is never usable and the bubble is unchanged (there's no placeholder).
- `submitPart` fails with `underReview` (defensive; shouldn't happen while holding the lock) → the existing submit-error path: snackbar `storyUnderReviewError`, stay in the chat, keep the typed text.
- `_errorMessage` gets the `underReview` case, so the `switch` stays exhaustive.

## 5. Notification taps (`NotificationRouterViewModel` + `HomeScreen`)

`story_continued`, first match wins:

| # | Condition | Outcome | UI |
|---|---|---|---|
| 1 | story missing | `notFound` | snackbar `storyNotFound` |
| 2 | story complete | `alreadyCompleted` | snackbar `errorStoryAlreadyCompleted` |
| 3 | `mature == true` and known minor (session **or stored year**) | `matureUnavailable` | snackbar `matureStoryUnavailable`; no `AgeGate.resolve`, no `AgeCheckScreen` |
| 4 | awaiting review | **`underReview`** (new) | snackbar `storyUnderReviewError` |
| 5 | user wrote the last part | `alreadyContinued` | as today |
| 6 | locked by someone else | `lockedByOther` | as today |
| 7 | `mature == true`, not session adult | gate: adult → `write`, minor → `matureUnavailable`, unknown → `askBirthYear` | as the complete list |
| 8 | otherwise | `write` | push `ChatScreen` |

`story_completed`:
1. not complete, or awaiting review (`reviewedAt == null`) → `notReadyYet` (`storyNotReadyYet`, unchanged text).
2. `mature != true` or session adult → `read`.
3. Known minor (also a stored minor year) → `matureUnavailable` without `resolve`.
4. Otherwise → the gate.

All of these are default `SnackBar`s with text only, shown on the home screen.

## 6. Copy / l10n

Italian `lib/l10n/app_it.arb` is the template; update `app_en.arb` too, then
run `flutter gen-l10n`.

### New

| Key | it | en | `@description` |
|---|---|---|---|
| `storyUnderReview` | In revisione... | Being reviewed... | Subtitle of a disabled incomplete-story tile whose latest part is still being checked; it can't be opened yet. Uses three dots like `storyBeingWritten`. |
| `storyUnderReviewError` | Questa storia è in revisione: riprova tra poco. | This story is being reviewed: try again in a moment. | Snackbar when a story can't be opened for writing because its latest part is still being checked (chat closed, or a notification tapped). |
| `matureStoryUnavailableLabel` | Non disponibile | Not available | Subtitle label on a disabled mature-story tile shown to a known minor, in both story lists (followed by the authors count in the completed list). Neutral: no mention of age or content. |

The plan wrote "In revisione…" with U+2026. This spec uses three ASCII dots to
match `storyBeingWritten`, which can sit in the next tile. Either reads the
same to TTS.

### Changed descriptions only (text unchanged)

| Key | New `@description` |
|---|---|
| `matureStoryLockedTitle` | Label of a mature story locked behind the age check, in both story lists: the subtitle of an incomplete story, next to the authors count in the completed list, and the title of a completed story without an AI title. |
| `matureStoryLockedLabel` | Screen-reader label of the padlock on a mature story tile (locked or unavailable), in both story lists. |
| `matureStoryUnlockHint` | Screen-reader tap hint on a locked mature story in either list; the platform adds the 'Double tap to' prefix, so this is just the verb. |
| `matureStoryAdultContent` | Screen-reader label of the open padlock on an unlocked mature story, in either list. |
| `matureStoryUnavailable` | Snackbar when an age check or a tapped notification denies a mature story to a minor. |
| `storyNotReadyYet` | Snackbar when a tapped notification's completed story hasn't finished its review yet. |

No keys are removed. `storyBeingWritten`, `storyWaitingForOthers`,
`storyNotStarted`, `authorsCount`, `genericError`, `storyNotFound`,
`noIncompleteStories` and `noCompleteStories` are reused unchanged.

## 7. Acceptance criteria (widget / VM tests, with the in-memory fakes)

Shared: "never calls the gate" means the fake `AgeGate`'s `resolve` call count
is 0. "Disabled" means `tester.widget<ListTile>(...).enabled == false` and
tapping it pushes no route.

**Incomplete list**
1. **In review:** a story with ≥1 part and no `partReviews` entry for its last position shows the position label, `storyUnderReview`, `Icons.hourglass_top`, is disabled, and the last five words are not found.
2. **Precedence 1 beats 2:** known minor + `mature: true` + awaiting review → the unavailable tile, not in review.
3. **Precedence 2 beats 3:** a story the user just wrote that is awaiting review shows in review, not `storyWaitingForOthers`. Once a verdict arrives on the stream it shows `storyWaitingForOthers`.
4. **Being written + mature, unknown age:** `Icons.lock` is shown instead of `TypingIndicator`, the subtitle is `storyBeingWritten`, the tile is disabled.
5. **Locked:** unknown age + `mature: true` + reviewed → `Icons.lock` (`primaryDark`, semantics label `matureStoryLockedLabel`), subtitle `matureStoryLockedTitle`, last words not found, enabled, `onTapHint == matureStoryUnlockHint`.
6. **Locked tap:** adult verdict → `ChatScreen` pushed; minor verdict → `matureStoryUnavailable` shown once and the tile becomes unavailable; spinner visible while resolving; a second locked tile's tap during the check is ignored.
7. **Unavailable:** known minor (stored minor year in the fake) → `Icons.lock`, `matureStoryUnavailableLabel`, last words not found, disabled, no `onTapHint`; tapping it never calls the gate and pushes nothing.
8. **Stored-year read pending:** a mature tile renders locked (not hidden, not unavailable).
9. **Unlocked:** session adult → last words visible, trailing `Icons.lock_open` with label `matureStoryAdultContent`, tap pushes `ChatScreen` without a gate call.
10. **Live:** pushing a new snapshot with the verdict turns in review into available, locked, unavailable or unlocked without rebuilding the screen.
11. **FAB:** a known minor whose only one-part story is their own flagged intro can create a story (`newStoryBlocked` not shown).
12. **Empty:** a list made only of in-review and/or unavailable stories doesn't show `noIncompleteStories`.

**Complete list**
13. A complete story with `reviewedAt == null` (even `mature: true`) is not found, not even after typing a query matching its title or keywords; it is not in `totalCounts`.
14. **Unavailable:** known minor → AI title shown (or `matureStoryLockedTitle` when null, never the first part), subtitle `"Non disponibile · N autori"`, `Icons.lock`, disabled, keywords visible, tap never calls the gate.
15. A search matching an unavailable story's keyword lists it, bold match included, and counts it in the tab label.
16. A room with only mature stories shows them to a known minor; `noCompleteStories` not found.
17. Unknown-age user resolved as minor by a tap: one `matureStoryUnavailable` snackbar, then every mature tile is unavailable and stays listed.

**Chat**
18. A fake `lockStory` throwing `StoryException(underReview)` → `ChatScreen` popped and `storyUnderReviewError` visible on the previous route.

**Notifications**
19. `continued` + awaiting review → `underReview` → `storyUnderReviewError` snackbar, no route.
20. `continued` + `mature` + stored minor year → `matureUnavailable`; gate never called.
21. `continued` + `mature` + unknown age → the gate; adult → `ChatScreen`.
22. `completed` + `reviewedAt == null` + `mature: true` → `notReadyYet`.
23. `completed` + `mature` + stored minor year → `matureUnavailable`; gate never called.

**l10n**
24. The three new keys exist in it and en with `@description` in the template; `flutter gen-l10n`, `flutter analyze` and `flutter test` (including `architecture_test.dart`) pass.

## 8. Decisions taken here (flag if you disagree)

- **Notification precedence.** `alreadyCompleted` is checked before the minor branch, and the minor branch before `underReview`, mirroring the list precedence.
- **Unlocked incomplete tile.** It gets the same trailing `lock_open` as the complete list, for consistency. The plan only said "normal tile".
- **In review icon.** `Icons.hourglass_top`, as the plan suggests. It is close to `hourglass_empty` (waiting for others); the subtitle tells them apart.
