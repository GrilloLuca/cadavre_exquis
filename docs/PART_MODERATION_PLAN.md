# Moderating each part on submit: technical analysis

Status: proposed 2026-10-22, revised twice the same day after owner decisions (below). Base branch `release/1.1.0`. Backend tasks B1–B7 are implemented and not yet deployed (`functions/src/moderation.ts`, `functions/src/index.ts`, `functions/scripts/review-incomplete-parts.js`, `functions/scripts/review-complete-stories.js`, rules comments; `npm test` passes). This revision adds backend deltas B8–B13 on top of them.

Builds on `docs/MATURE_INLINE_PLAN.md` (story-level `mature`, locked tiles), `docs/AGE_SIGNALS_PLAN.md` (`AgeGate`) and `docs/STORY_KEYWORDS_PLAN.md`.

**User story.** "As a minor, I want each single chapter (part) of a story to be moderated by AI every time it is submitted, and no longer only when the story is completed, so I avoid seeing sensitive content among the last 5 words shown in the chat."

**Owner decisions (2026-10-22)**
1. An incomplete story with `mature == true` behaves like a completed mature story:
   - unknown-age users see it locked and go through `AgeGate`;
   - adults open it.

   A flagged part sets the story-level `mature` immediately.
2. **Until a story has been reviewed, nobody can open it**: not minors, not adults, not the next writer. This replaces the earlier "pending: neutral placeholder, story stays playable" design.
3. **Known minors see mature stories as locked, disabled tiles** instead of not seeing them at all, in both the incomplete and the complete list (D4b). This reverses the "known minors don't see mature stories" rule of `docs/MATURE_INLINE_PLAN.md` D5 and `docs/MATURE_INLINE_UI_SPEC.md` §5.

---

## 1. Current flow (before this feature, facts from the code)

### 1.1 Submitting a part
- `StoryRepositoryFirestore.submitPart` (`lib/data/repositories/story/story_repository_firestore.dart`) runs a transaction. It checks status, position, lock and consecutive turn, then writes:
  - `parts` (the earlier parts sent back exactly as read, plus the new `{position, text, author, timestamp}`);
  - `currentPosition`, `status` (`complete` on the 4th part);
  - `lockedBy: null`, `lockedAt: null`, `updatedAt`.
- `lockStory` is a transaction that writes `lockedBy` and `lockedAt`. The chat takes the lock as soon as it opens (`ChatViewModel.lock`); a lock error shows a snackbar and pops the screen (`chat_screen.dart` ~l.72).
- `isValidSubmit` and `isValidLockChange` in `firestore.rules` check the same conditions as the client. All server fields are protected because no client `hasOnly` list includes them.

### 1.2 Functions on `stories/{storyId}` (us-central1)
| Function | Fires when | Writes / does |
|---|---|---|
| `normalizeStory` (create) | create | `roomId`/`language` if missing |
| `reviewCompletedStory` | status becomes `complete` and no `reviewedAt` (`needsCompletionReview`) | `title`, `mature` (ORed, never downgraded), `reviewedAt`; completion push from the run that set `reviewedAt` |
| `moderateStoryPart` (new, B3) | a part was added, the 4th included (`addedPartFor`) | `partReviews.<position>`; `mature: true` on a mature verdict |
| `notifyStoryContinued` | a part was added and the story is still incomplete | `story_continued` push to earlier authors |
| `extractStoryKeywords` | a part was added, the 4th included | `keywords`, `keywordsPartCount` |
| `anonymizeDeletedUser` (Auth v1) | account deleted | `parts[].author`, locks |

None of them retries today; failures are logged and left to the backfill scripts.

### 1.3 Where story content is shown
- The last five words (`Story.lastFiveWords`, client-computed) appear in:
  - the subtitle of `IncompleteStoriesScreen` for `available` stories (a live stream);
  - the `ChatScreen` bubble (a snapshot taken when the chat opens).
- Keywords appear in the chat only, and are child-safe by prompt.
- The full text appears only in `StoryReadScreen`, for complete stories reached from `CompleteStoriesScreen` or the `completed` push.
- Push texts carry only a nickname and the AI title.
- `NotificationRouterViewModel`: `continued` → `write` with no mature check; `completed` → `notReadyYet` while `mature == null`, then the age gate.
- The mature gate lives in `CompleteStoriesViewModel`: a quiet stored-birth-year read, `unlock` → `AgeGate.resolve`, and session verdicts shared through `AgeGate`.

---

## 2. Design

### D1. Story `mature` (unchanged from the first revision, implemented)
- It only ever moves towards `true`:
  - missing → `true` (any part flagged);
  - missing → `false` (completion review only, when nothing was flagged);
  - `false` → `true`.

  It never goes from `true` to `false`.
- Incomplete stories have `mature: true` or no `mature`.

### D2. Server fields (implemented, plus one change in D5)
- `partReviews: { <position>: "safe" | "mature" }`: top-level, server-only, one entry per reviewed part.
- `reviewedAt`: the completion review's "done" marker. It replaces "`mature` is a boolean", so a story flagged early still gets its title and completion push.

### D3. What "reviewed" (openable) means

| Story | Openable when | Notes |
|---|---|---|
| incomplete, 0 parts | always | nothing to review |
| incomplete, ≥ 1 part | the **latest** part has a verdict: `parts.last.position` is a key of `partReviews` | This is what the owner asked for, and it's the only text shown in the writing flow. It's also what the rules can check cheaply (D7). Earlier parts: in the new flow a part can only be written after the previous one was reviewed, so "latest reviewed" implies "all reviewed" for every story written after the deploy. Legacy in-progress stories get all their parts reviewed by the backfill. |
| complete | `reviewedAt` is set | The completion review read the whole text, last part included (D5). It replaces today's "`mature` is a boolean" visibility test, which a part flag (`mature: true` before the review) would now satisfy too early. |
| complete, legacy (reviewed before `reviewedAt` existed) | after B12 marks it | B12 sets `reviewedAt` on complete stories that have a boolean `mature`, no `reviewedAt` and no `partReviews` (so no part-moderation era). Without B12 they would disappear from the new app's complete list. |

Mature gating (D1) applies **on top of** this: a reviewed story with `mature == true` is locked for everyone who isn't a session adult. It is disabled for known minors (D4b) and opens the age check for unknown-age users.

`Story` gets a single getter the app uses everywhere, e.g. `bool get awaitingReview`: `isComplete ? reviewedAt == null : parts.isNotEmpty && !partReviews.containsKey(parts.last.position)`.

### D4. What the app shows for a story awaiting review

| Surface | Awaiting review | Reviewed, `mature != true` | Reviewed, `mature == true` |
|---|---|---|---|
| Incomplete list | tile shown, **disabled**: position label, `Icons.hourglass_top` (or similar), subtitle `storyUnderReview` ("In revisione…"), no last words, not tappable. For a known minor on a story that is already `mature == true` (an earlier part flagged), the minor's "unavailable" tile shows instead (precedence below). | as today | known minor: disabled "unavailable" tile (D4b); unknown age: locked tile, tap → gate; session adult: normal tile |
| Chat | can't be reached: `lockStory` refuses with `StoryErrorCode.underReview`, so the existing lock-error path shows a snackbar (`storyUnderReviewError`, "Questa storia è in revisione: riprova tra poco.") and closes the screen | as today | adults only, as today |
| `story_continued` push | not sent until the verdict lands (B9). If it is opened while the story is awaiting review anyway (e.g. a later part is pending), new outcome `underReview` → the same snackbar | `write`, as today | known minor: `matureUnavailable` snackbar, no gate; otherwise through the gate (F5) |
| Complete list | **hidden** (client-side filter on `reviewedAt`), as unreviewed stories are today | as today | known minor: disabled "unavailable" tile (D4b); unknown age: locked, tap → gate; session adult: unlocked |
| `completed` push | only sent by the run that sets `reviewedAt`. The router's `notReadyYet` test becomes `awaitingReview` instead of `mature == null` | read | known minor: `matureUnavailable`; otherwise the gate (as today) |

**Precedence of the incomplete tile states**, first match wins:
1. `mature == true` and known minor → **unavailable** (D4b). This comes before "in review" because `mature` is never downgraded: whatever the pending verdict says, the story stays unavailable to them.
2. Awaiting review → disabled "in review".
3. `beingWritten` / `waitingForOthers` → as today (disabled, with the reason). Show the padlock as the leading icon if `mature == true` and the user isn't a session adult.
4. `mature == true` and not session adult → locked, tap → gate.
5. Otherwise available.

The complete list only has steps 1, 4 and the normal/unlocked tile, since awaiting-review stories aren't listed there. Both lists are live streams, so a tile switches state on its own when a verdict lands, typically after a few seconds.

### D4b. Known minors: locked, disabled tile with the reason shown, no tap action (reverses `MATURE_INLINE_PLAN.md` D5)
- **Who is a known minor:** unchanged. A stored birth year that isn't adult (read quietly when the screen opens via `AgeGate.storedBirthYear`) or a session minor verdict (`AgeGate.isSessionMinor`).
- **Minor tile vs unknown-age tile.** Both show `Icons.lock` (semantics `matureStoryLockedLabel`) and the same title: the child-safe AI title, or `matureStoryLockedTitle` without one. Neither shows any story text or the last words. The differences:

  | | Unknown age | Known minor |
  |---|---|---|
  | enabled | yes (button semantics, `onTapHint: matureStoryUnlockHint`) | **no** (`ListTile.enabled: false`, greyed like the incomplete list's disabled tiles) |
  | subtitle | as today (`matureStoryLockedTitle · authors`, or the position label/status in the incomplete list) | new short label `matureStoryUnavailableLabel` ("Non disponibile" / "Not available") ` · authors` in the complete list, or instead of the last words in the incomplete list |
  | tap | `AgeGate.resolve` → age flow | nothing; never calls `AgeGate` (so no system sheet or birth-year screen) |

- **Recommendation: disabled with the reason in the subtitle, rather than a tappable tile that shows a snackbar.** It's the pattern the incomplete list already uses for `beingWritten` and `waitingForOthers` (disabled, reason shown). The reason is readable without tapping, also by screen readers, and there's no repeated snackbar. The wording stays neutral: "not available", no age or content explanation, the same principle as `matureStoryUnavailable`. Alternative (Q8): keep the tile enabled and show the `matureStoryUnavailable` snackbar on tap without calling the gate. That's a one-condition change.
- **Minor verdict from a tap** (an unknown-age user resolved as minor): the existing snackbar `matureStoryUnavailable` shows once, then **every** mature tile in both lists switches to the minor tile (via the shared session minor set). They no longer disappear.
- **Before the quiet stored-year read finishes**, mature tiles render as unknown-age locked tiles. The old rule "hidden until the read finishes" existed only to stop a known minor seeing a tile flash in, and that no longer applies. A tap in that window is safe: `AgeGate.resolve` reads the stored year itself and answers `minor` without calling the platform. The tile then switches to the minor state, possibly after a single snackbar.
- **Search (complete list):** mature stories now stay in the list for known minors, so the query can match them on AI title and keywords, both child-safe by prompt, and show the disabled tile. The comment and test asserting "a hidden mature story can never come back through a search" are replaced.
- **Empty states:** a room whose only completed stories are mature now shows those tiles to a minor instead of `noCompleteStories`. `totalCounts` counts them.
- **Build flag:** `--dart-define=MATURE_VISIBLE_TO_MINORS=false` (default `true`) restores the old D5 behaviour for testing: known minors don't see mature stories in either list, search, tab counts or empty states (`MatureTileState.hidden`), a minor verdict shows the snackbar once and then hides them, and tiles stay locked while the stored year loads; notifications and `canCreateStory` behave the same in both modes. Read once in `lib/config/dependencies.dart` (`AppConfig`).
- **`canCreateStory`** (one-waiting-intro rule) still ignores `mature == true` stories. A minor's own flagged introduction now shows as their unavailable tile, but it must not block them from starting a new story.
- **No backend change.** The push routing is client-side. The server already sends pushes regardless of age, the rules don't involve age (Q5), and B8–B13 are unaffected.

### D5. The completing part is reviewed by `reviewCompletedStory`, in the same transaction (change to B3/B4)
- This closes the developer's known gap: a complete story whose part-4 review failed was picked up by neither backfill.
- It also closes the completion race: the completion review could set `mature: false` and make the story openable seconds before a part-4 `mature` verdict.
- `moderateStoryPart` skips a part that completes the story (`after.status === "complete"`).
- `reviewCompletedStory` runs `reviewStory(after)` and `reviewPart(lastPart)` in parallel, then writes in one transaction:
  - `partReviews.<last position>` (if missing);
  - `title` (if missing);
  - `mature = stored true || review.mature || partVerdict == "mature"`;
  - `reviewedAt`.

  If either call fails, nothing is written and the story stays awaiting review (then retried, D6).
- `review-complete-stories.js` uses the same combined path, so backfilled stories look the same.
- Cost is unchanged: still one part call and one story call on completion.

### D6. Failures: retry automatically, keep the manual backfill as the last resort
A failed review now blocks a story for everyone, so logging and waiting for a manual script is no longer enough.
- **Recommended: `retry: true` on `moderateStoryPart` and `reviewCompletedStory`.**
  - The handlers are already idempotent: `savePartReview` and `reviewFields` refuse a second verdict, and only the run that stored it notifies.
  - Each handler **throws** on Gemini or transaction errors so the event is redelivered with backoff. Eventarc retries Firestore events for up to 24 hours; verify this for 2nd-gen triggers at implementation.
  - It gives up quietly on events older than a cap (e.g. 6 h, by `event.time`), logging `"Part review gave up"` / `"Story review gave up"`, so a permanent error (e.g. a malformed response every time) doesn't burn calls for a day.
  - Before calling Gemini, a retried event checks for an existing verdict (a cheap `get`), so redeliveries after a success don't call the model.
  - Notification failures are caught and logged, never thrown: a retry would find the verdict stored and never re-notify anyway.
- **Manual backfill stays** (`review-incomplete-parts.js`, `review-complete-stories.js`) for stories past the cap and for the rollout. Add a log-based alert on the "gave up" messages so someone knows to run it.
- **Rejected: a scheduled sweeper** (`onSchedule` every N minutes running `partsToReview`). It has no indexable "missing verdict" query, so it scans every incomplete story each run, and it adds a second code path that writes verdicts. Retries cover transient outages, which is the realistic failure. A sweeper can be added later if alerts fire often (open question Q2).
- Safety blocks already count as `mature`, not as errors, so they don't block.

### D7. Lock and write while a story awaits review: enforced by the rules too
- **Who can be inside the chat when a new part arrives? Nobody else.** The lock is exclusive, and a submit releases it in the same write that adds the part, so the part becomes pending with no lock held. The writer who just submitted leaves the chat on success (existing behaviour). An expired lock taken over by someone else makes the old holder's submit fail (`freeForMe`), as today.
- **The next writer during the pending seconds**: the list tile is disabled. If they arrive by push or with a stale list, `lockStory` refuses (`underReview`) and the chat closes with the snackbar.
- **Rules: yes, enforce.** Add to the lock branch of `isValidLockChange` and to `isValidSubmit`:
  ```
  function lastPartReviewed(data) {
    return data.parts.size() == 0
      || data.parts[data.parts.size() - 1].position in data.get('partReviews', {});
  }
  ```
  - Lock (`newLock == myEmail()`) requires `lastPartReviewed(resource.data)`.
  - Submit requires `lastPartReviewed(before)`. Submit doesn't require holding a lock, so without this an old or modified client could skip the lock.
  - Unlock is unaffected: a holder can always release.
  - The rules need no `get()` and add no reads.
  - Why rules and not app-only: it also stops **old app versions** from opening pending stories in the chat, the main remaining leak of unmoderated words (they still show them in the list subtitle). Old versions get a generic error for those few seconds, which is acceptable.
  - Admin SDK writes (functions, scripts) bypass the rules.
- The client mirrors the check (`StoryErrorCode.underReview` in `lockStory` and `submitPart`), so the app shows a precise message instead of a permission error.
- **Minors mid-turn when a story turns mature** can no longer happen: a story becomes mature only through a verdict, and nobody holds the chat during the verdict. The old Q3 is settled.

### D8. `story_continued` push after the verdict, not on submit (change)
Sending it on submit would bring the other authors straight into a story nobody can open yet.
- The push is sent by `moderateStoryPart` after `savePartReview` stored the verdict (only the run that stored it). It goes to the same recipients (`recipientsFor(after.parts without the new one, newAuthor)`), with the same text.
- It's sent for `mature` verdicts too: the text is neutral, and the router gates the tap (F5).
- `notifyStoryContinued` is deleted (`firebase deploy --only functions` asks to confirm deleting it).
- If retries give up and the backfill reviews the part later, the backfill doesn't notify (as `review-complete-stories.js`). Accepted.
- The completing part has no `story_continued` push today either; `notifyStoryCompleted` is unchanged.

### D9. Cost
Unchanged from the first revision: at most 4 small part calls per story, plus retries during outages (bounded by the age cap).

---

## 3. Queries, rules, indexes, legacy, old app versions
- **Queries: no change.** The incomplete list keeps its `status` + room query; awaiting-review and mature states are computed in the ViewModel. The complete list keeps `mature in [false, true]` and additionally drops `reviewedAt == null` on the client. Filtering on `reviewedAt` in Firestore would need an inequality and new indexes.
- **Rules:** `lastPartReviewed` on lock and submit (D7), plus comment updates. The client still can't write `mature`, `partReviews` or `reviewedAt`.
- **Indexes:** none.
- **Legacy in-progress stories** have no `partReviews`, so they are **unopenable for every app version once the rules deploy** and for the new app until backfilled. Hence the strict rollout order below.
- **Legacy complete stories** have no `reviewedAt`, so they are hidden from the new app's complete list until B12 marks them.
- **Old app versions**:
  - after the rules deploy, they can't lock or submit a pending story;
  - they still show the last words of a pending part in the list subtitle for its few seconds, and of flagged parts indefinitely;
  - they don't gate incomplete mature stories;
  - their complete list shows a flagged-by-parts story as locked before `reviewedAt` (no title).

  There is no minimum-version check (Q4).

## 4. Rollout order (strict)
1. **Deploy functions**: B1–B7, B8–B11. This includes deleting `notifyStoryContinued`. Every app version keeps working; `story_continued` pushes now arrive a few seconds later.
2. **Backfill, all mandatory before steps 3 and 4:**
   1. `node scripts/review-incomplete-parts.js` (dry run), then `--write`; repeat until it reports 0 candidates.
   2. `node scripts/review-complete-stories.js --mark-legacy` (dry run), then `--write` (B12).
   3. `node scripts/review-complete-stories.js --write` for completed stories whose review failed.
3. **Deploy rules** (B13). Before step 2.1, every in-progress story would refuse locks for every app version.
4. **Release the app** (F1–F7). Before step 2, every in-progress story would show "in review" forever and the reviewed legacy complete stories would vanish.
5. Watch the "gave up" alert; re-run step 2.1 if it fires.

---

## 5. Tasks

### Backend: done (B1–B7, the first revision)
B1 shared criterion + `reviewPart`; B2 `savePartReview`; B3 `moderateStoryPart`; B4 `reviewedAt` marker; B5 `review-complete-stories.js` candidates; B6 `review-incomplete-parts.js`; B7 rules comments + docs. Implemented, tests passing. B3 and B4 are amended by B8 and B10.

### Backend: new (hand to `backend-developer`)

**B8. `moderateStoryPart`: skip the completing part, retry, age cap**
- `partToModerate(before, after)` (pure): the added part, or undefined when `after.status === "complete"`.
- Options: `retry: true`. Before calling Gemini, check the current doc for a verdict and return if found.
- On Gemini or transaction errors: throw if the event is younger than the cap (e.g. 6 h), otherwise log `"Part review gave up"` and return.
- Update the doc comment ("failures are retried…") and the moderation.ts header.
- AC: tests cover
  - `partToModerate` (undefined for parts 4 and for lock, server-field and anonymization writes; defined for parts 1–3);
  - a pure `shouldRetry(eventTime, now)` at the cap boundary.

**B9. `story_continued` push after the verdict**
- `moderateStoryPart` notifies the earlier authors only when `savePartReview` returned true. Recipients come from the parts before the new one.
- Notification errors are caught and logged.
- Delete `notifyStoryContinued`; keep `notifyIfContinued` or rename it to a helper that takes the story data.
- AC: tests that
  - the recipients helper is called only on a stored verdict (pure `continuedRecipients(after)`: the new author is excluded and duplicates are removed, reusing `recipientsFor`);
  - no push goes out for the completing part;
  - the backfill script doesn't notify.

**B10. `reviewCompletedStory` reviews the last part too, atomically; retry**
- `reviewStory` and `reviewPart(last part)` in parallel.
- One transaction with a pure `completionFields(data, review, partVerdict)`: `partReviews.<last>` if missing, `title` if missing, `mature` OR of the stored value, the review and the part verdict, and `reviewedAt`. Nothing is written once `reviewedAt` is set.
- `retry: true` + the same age cap (`"Story review gave up"`). It throws on either call failing; notification errors are caught.
- AC: tests cover
  - part `mature` + review `false` → `mature: true`;
  - stored `true` stays;
  - an existing part verdict isn't overwritten;
  - `reviewedAt` already set → no fields and no notify.

**B11. `review-complete-stories.js` uses the B10 path**
- It reviews the story and its last part with the same `completionFields`, and never notifies.
- AC: the dry run prints both verdicts; a re-run after `--write` finds 0 candidates.

**B12. `review-complete-stories.js --mark-legacy`**
- Sets `reviewedAt` (server timestamp) on complete stories with a boolean `mature`, no `reviewedAt` and no `partReviews`. Dry run by default.
- AC: pure `isLegacyReviewed(data)` tested (true for the legacy shape; false with `partReviews`, with `reviewedAt`, or without `mature`); a re-run marks 0.

**B13. Rules: no lock or submit while the last part awaits review**
- `lastPartReviewed(data)` (D7), required by the lock branch of `isValidLockChange` and by `isValidSubmit`; comments updated.
- AC (emulator, manual; there's no rules test suite):
  - lock and submit refused on a story whose last part has no verdict;
  - allowed once it has one;
  - allowed on a story with 0 parts;
  - unlock by the holder always allowed;
  - a client write to `partReviews` still refused.

### Frontend (hand to `frontend-developer`; replaces the first revision's F1–F7)

**F1. Domain, mapping, repository**
- `Story.partReviews` (`PartVerdict { safe, mature }`, tolerant parsing), `Story.reviewedAt` (`DateTime?`), `Story.awaitingReview` (D3).
- `StoryErrorCode.underReview`, thrown by `lockStory` and `submitPart` when `awaitingReview`. Fakes support all of it.
- AC: unit tests for every row of D3 (including legacy and malformed fields); repository tests refuse lock and submit with `underReview`.

**F2. Shared mature-visibility helper** (changed by D4b)
- Extract from `CompleteStoriesViewModel`, for reuse by both lists and the router:
  - the quiet stored-birth-year read;
  - `isKnownMinor` / `isSessionAdult`;
  - the unlock / birth-year flow.
- One per-story state: `MatureTileState { none, unavailable, locked, unlocked }`:
  - `none` for `mature != true`;
  - `unavailable` for a known minor;
  - `locked` for unknown age, which includes "stored-year read not finished";
  - `unlocked` for a session adult.
- `unlock` returns `minor` straight away for a known minor, without calling `AgeGate` (as today). The "hide mature stories" logic (`hideMature`, hide-until-loaded) is **removed**.
- AC:
  - helper unit tests for each state, including the read still running (`locked`) and a stored minor year (`unavailable`, `AgeGate.resolve` never called, checked with the fake's call counter);
  - a session minor verdict turns every mature story `unavailable`.

**F3. Incomplete list**
- New statuses `underReview` and `unavailable` in `IncompleteStoryStatus`, with the D4 precedence (unavailable > underReview > beingWritten / waitingForOthers > locked > available).
- Tiles:
  - `underReview`: disabled, `storyUnderReview`;
  - `unavailable`: disabled, padlock, `matureStoryUnavailableLabel` instead of the last words;
  - `locked`: padlock, `matureStoryLockedTitle` instead of the last words, tap → age flow → `ChatScreen` on adult, snackbar on minor (the tiles then turn `unavailable`).
- `canCreateStory` ignores `mature == true` stories.
- AC: VM and widget tests for every precedence case, including:
  - a known minor on a mature story that also awaits review → `unavailable`;
  - a known minor's tile is disabled and tapping it doesn't call `AgeGate`;
  - the live stream turning `underReview` into `available`, `locked` or `unavailable`;
  - a known minor whose own flagged intro is listed as `unavailable` and doesn't block `createStory`.

**F4. Chat**
- Map `underReview` from the lock command to `storyUnderReviewError` (existing snackbar + pop). Remove the placeholder idea; the bubble is unchanged.
- AC: widget test: a lock refused with `underReview` shows the snackbar and pops.

**F5. Notification router**
- `continued`:
  1. `mature == true` and known minor → `matureUnavailable` (no gate);
  2. awaiting review → new outcome `underReview` (snackbar);
  3. `mature == true` → the gate via F2;
  4. otherwise `write`.
- `completed`:
  - `notReadyYet` when `awaitingReview` (instead of `mature == null`);
  - known minor → `matureUnavailable` without calling `resolve`, now also for a stored minor year (via F2), not only a session minor.
- AC: VM tests for each branch; known-minor branches assert `AgeGate.resolve` is never called.

**F6. Complete list** (changed by D4b)
- Drop stories with `reviewedAt == null` before the mine/others split and the search.
- **Keep** mature stories for known minors, as `unavailable` tiles: disabled, padlock, title or `matureStoryLockedTitle`, subtitle `matureStoryUnavailableLabel · authors`, no tap action.
- Replace the VM doc comment and the test "a hidden mature story can never come back through a search" with:
  - mature stories match the query for known minors too and show as `unavailable`;
  - `totalCounts` includes them.
- AC:
  - a complete story with `mature: true` and no `reviewedAt` is never listed, not even via search;
  - a known minor sees a mature story as a disabled tile whose tap doesn't call `AgeGate`;
  - a room with only mature stories shows them to a minor, not `noCompleteStories`;
  - an unknown-age user resolved as minor sees the snackbar once, then `unavailable` tiles that stay listed.

**F7. l10n**
- `storyUnderReview` (it "In revisione…", en "Being reviewed…").
- `storyUnderReviewError` (it "Questa storia è in revisione: riprova tra poco.", en "This story is being reviewed: try again in a moment.").
- `matureStoryUnavailableLabel` (it "Non disponibile", en "Not available": the subtitle of a known minor's tile, neutral, no age or content explanation).
- All with descriptions. Update the `@` descriptions of `matureStoryLockedTitle` and `matureStoryUnavailable` (no longer "completed stories list" only, and no "then hidden").
- AC: `flutter gen-l10n`, `flutter analyze` and `flutter test` (including `architecture_test.dart`) pass.

**F8. Docs**
- Mark the reversal in `docs/MATURE_INLINE_PLAN.md` (D5) and `docs/MATURE_INLINE_UI_SPEC.md` (§4–§5) as superseded by D4b. Done in this revision as notes; the frontend developer keeps them in sync if D4b changes.

A short UI spec for the "in review", locked and unavailable tiles (both lists) should come before F3/F6.

---

## 6. Risks
1. **A failed review blocks a story** until the retry succeeds or the backfill runs (D6). Mitigated by retries, the age cap and the alert. The worst case is a Gemini outage longer than the cap, after which someone has to run the backfill.
2. **Strict rollout coupling** (§4): rules or app before the backfill make every in-progress story unopenable, and the app before B12 hides the legacy complete stories.
3. **Latency**: every part now costs the next writer a few seconds of "in review". That's normally invisible, because the next writer rarely arrives within seconds.
4. **Old app versions** still show last words in the list subtitle and don't gate incomplete mature stories (no minimum-version check).
5. **App-side age gate only**: any signed-in client can read any story (unchanged).
6. **Stalled mature stories** in rooms without adults; **over-gating** from a false positive, which is permanent because `mature` is never downgraded.
7. **Lost `story_continued` push** for parts reviewed by the manual backfill.
8. **Minors learn that mature stories exist** (D4b): they see a padlock, the AI title and the keywords via search. Titles and keywords are child-safe by prompt, so the exposure is the existence of the story, which the owner accepted. Any future surface that shows story text must check the tile state.

## 7. Open questions remaining (recommended default in bold)
- **Q1. Enforce "no lock or submit while awaiting review" in the rules (B13)?** **Default: yes** (D7). It's the only way to cover old app versions in the chat.
- **Q2. Failure strategy:** `retry: true` with an age cap, or also a scheduled sweeper? **Default: retries (cap 6 h) + alert + manual backfill**; add a sweeper only if the alert fires repeatedly.
- **Q3. Send the `story_continued` push for parts judged mature?** **Default: yes** (neutral text; the tap is gated).
- **Q4. Old app versions:** accept, or add a minimum-version check (a separate story)? **Default: accept**, and plan the minimum-version check next.
- **Q5. Server-side age enforcement** (refuse locks on mature stories for stored-minor birth years)? **Default: no**.
- **Q6. Show "in review" tiles at all, or hide awaiting-review stories from the incomplete list?** **Default: show them disabled**, so players see the story they just wrote and don't create duplicates.
- **Q7. Stalled mature stories / feedback to the writer of a flagged part?** **Default: leave them / no feedback.**
- **Q8. Known minor's tile: disabled with "Non disponibile" in the subtitle, or enabled with the `matureStoryUnavailable` snackbar on tap (never calling `AgeGate`)?** **Default: disabled with the reason** (D4b), the pattern of the incomplete list's other disabled tiles.
- **Q9. Should a known minor's tile show the AI title** (child-safe) or always the generic `matureStoryLockedTitle`? **Default: the AI title**, as on unknown-age locked tiles today. Showing it to unknown-age users but not to minors would make the minor tile reveal the user's age state to anyone looking at the screen, for no safety gain.
