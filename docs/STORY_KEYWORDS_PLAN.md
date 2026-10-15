# Keywords for incomplete stories: technical analysis

**User story.** As a player, I want to see up to 4 keywords instead of the title of an incomplete story, so that I have some context to continue it.

**Scope decided:** the keywords are shown **only in the chat screen** (where the player writes), not in the incomplete stories list, and they are extracted from **all the parts written so far**.

**Status:** backend (B1, B2 code), data layer (F1) and chat UI (F2) implemented, not deployed or committed; device check pending. Target: Android + iOS (web gets it for free, it only reads a field).

---

## 1. Current state (facts from the code)

- Incomplete stories have **no title**. `title` (and `mature`) are written by `reviewCompletedStory` only once `status` becomes `complete` (`functions/src/index.ts`).
- In the incomplete list (`IncompleteStoriesScreen._buildList`) the `ListTile` title is the **position label** ("Sviluppo 1"…) and the subtitle is the status, or `"...<lastFiveWords>"`.
- In `ChatScreen` the AppBar title is the position label, and the body shows only `story.lastFiveWords`. That's the whole context a player gets today.
- Part text is **not moderated** until the story is complete. Players are mostly children (see `REVIEW_INSTRUCTION`).
- `isValidSubmit` / `isValidLockChange` / `isValidCreate` in `firestore.rules` list the keys a client may touch with `hasOnly`, so a field written only by the Admin SDK can't be forged by a client. No rule change is needed.
- `submitPart` uses `transaction.update` with explicit fields, so it doesn't overwrite a field it doesn't know about.
- Three functions already react to `stories/{id}` updates (`reviewCompletedStory`, `notifyStoryContinued`) or creates (`normalizeStory`). All of them return early on irrelevant changes.

---

## 2. Behaviour

The incomplete stories list doesn't change.

| Story state | Chat screen |
|---|---|
| No parts yet | As today (`chatFirstWriterTitle`) |
| ≥ 1 part, keywords present | Keywords, e.g. `drago` `faro` `tempesta` `segreto`, shown above the "story so far" bubble |
| ≥ 1 part, keywords not ready yet / failed / legacy story | As today |

Keywords are generated **after every part except the last** (after the epilogue the story is complete and gets its title). So at most 3 Gemini calls per story.

Keywords take a few seconds to arrive. `ChatViewModel` holds the `Story` it was opened with and doesn't listen to the document, so a player who opens the story in that window sees today's screen (§5.2).

---

## 3. Data model (`stories/{id}`)

| Field | Type | Written by | Notes |
|---|---|---|---|
| `keywords` | `string[]`, 0–4 items | Cloud Function only | `[]` means "generated, nothing usable" (refused or empty); missing means "never generated" |
| `keywordsPartCount` | `int` | Cloud Function only | Number of parts the keywords were computed from; used server-side to drop out-of-order results (§4.3). The app doesn't read it |

Both fields stay on the document after completion. They're harmless and cost nothing to keep.

**Security rules:** no change. Add a comment next to `isValidSubmit` saying that `keywords`/`keywordsPartCount` are written by `extractStoryKeywords` only and that clients can't write them because of the `hasOnly` lists.

---

## 4. Backend (`functions/src/`)

Put the code in a new `keywords.ts` (like `notifications.ts`), exported from `index.ts`. It reuses `client()`, `MODEL`, `LANGUAGE_NAMES`, `DEFAULT_LANGUAGE` and `BLOCKED_FINISH_REASONS`, so these move to a small shared module (e.g. `gemini.ts`), or get exported from `index.ts`.

### 4.1 Trigger: `extractStoryKeywords`, a new `onDocumentUpdated("stories/{storyId}")`

```ts
// Pure, exported for tests: the part count to extract keywords for, or
// undefined if this update isn't "a part was added and the story goes on".
export function keywordsPartCountFor(before, after): number | undefined {
  const n = (after.parts ?? []).length;
  if (n !== (before.parts ?? []).length + 1) return undefined;
  if (after.status !== "incomplete") return undefined;
  return n;
}
```

This is the same condition as `notifyIfContinued`, so lock changes, the function's own write, and completion all exit immediately. The function's write of `keywords` re-triggers all three update functions, and all of them return early on it.

Keep it a separate function instead of folding it into `notifyStoryContinued`: a Gemini failure must not affect notifications, and vice versa.

### 4.2 `extractKeywords(data): Promise<string[]>`

- Input: **all parts written so far** joined by `\n\n` (see decision D1), in the story's `language`.
- Output: structured JSON, `responseSchema = { keywords: ARRAY of STRING }`, `temperature` ~0.4.
- Instruction (draft):
  > You read the beginning of a short story written collaboratively by several players, mostly children and teenagers. Give at most 4 keywords in {language} that capture its characters, setting and situation, so the next player knows what the story is about. Each keyword is one or two words, lowercase unless it's a proper name, no punctuation, no quotes. Everyone sees the keywords, so they must always be suitable for a 10-year-old: no sexual or suggestive words, graphic violence, gore, profanity, slurs, drugs, alcohol, self-harm or suicide. If the story contains such content, use neutral words about its plot, characters or setting instead, or give fewer keywords.
- Blocked prompt / safety finish reason → `[]` (same check as `reviewStory`).
- Network/API error → throw. The trigger logs it and leaves the previous keywords in place (§4.4).

`cleanKeywords(raw: unknown): string[]` (pure, exported, tested): keep strings only, trim, strip quotes/`#`/punctuation at the ends, drop empties, cap each at ~24 chars, case-insensitive de-duplication, at most 4.

### 4.3 `saveKeywords(storyId, partCount, keywords)`: transaction

Write `{ keywords, keywordsPartCount: partCount }` only if:
- the story is still `incomplete`, and
- `parts.length === partCount` (nobody added a part meanwhile; otherwise a newer event is computing fresher keywords), and
- the stored `keywordsPartCount` (if any) is `< partCount` (protects against duplicate or out-of-order events).

This follows the project rule that read-modify-write on stories goes through transactions, and makes the function idempotent.

### 4.4 Failure handling

On error: `logger.error("Keyword extraction failed", { storyId, error })` and return, without retrying. The app falls back to the position label, or keeps the previous part's keywords, which still describe the story. Turning on retries for a Gemini call isn't worth it here.

### 4.5 Backfill: `functions/scripts/extract-incomplete-keywords.js`

Incomplete stories with ≥ 1 part and no `keywords` field: computes and saves keywords. Dry run by default, `--write` to save, same pattern as `review-complete-stories.js`. It calls `extractKeywords`/`saveKeywords` directly.

### 4.6 Function tests (`functions/test/keywords.test.js`, `node --test`)

- `keywordsPartCountFor`: part added (1→2) ✔; lock change ✘; last part (status `complete`) ✘; keyword write itself ✘; legacy docs without `parts` ✘.
- `cleanKeywords`: >4 items, duplicates with different case, quotes/punctuation, empty strings, non-strings, non-array input.

---

## 5. App (Flutter, MVVM)

### 5.1 Domain and data
- `Story.keywords`: `final List<String> keywords;`, default `const []`, documented like `title` (set by `extractStoryKeywords` shortly after each part; empty until then, on failure, or for legacy stories).
- `storyFromSnapshot`: read `data['keywords']` tolerantly (missing or not a list → `[]`, keep `String` entries only, `take(4)`). Legacy documents lack the field.
- `FakeStoryRepository`: no change needed beyond letting tests build stories with `keywords`.

### 5.2 Chat screen (`ChatScreen`), the only UI change
- A row of up to 4 `Chip`s (`Wrap`, cream style consistent with `MessageBubble`) above the "story so far" bubble, only when `story.keywords` is non-empty. With no parts, the screen is unchanged.
- The AppBar keeps the position label. `IncompleteStoriesScreen` is not touched.

**Known gap:** `ChatViewModel.story` is the snapshot passed in from the list (or from a notification tap), and the screen doesn't listen to the document. If the keywords weren't saved yet when the player opened the story, they don't appear until the screen is reopened. In practice the next player rarely arrives within seconds of the previous submit, so v1 accepts this. If it shows up on device, add `StoryRepository.storyStream(id)` and have `ChatViewModel` update `keywords` from it (open decision D6).

### 5.3 Localization
The keywords are content in the story's language, not UI text. Add one string for accessibility/semantics, e.g. `storyKeywordsLabel`: IT "Parole chiave", EN "Keywords", in both `.arb` files, then run `flutter gen-l10n`.

### 5.4 Tests
- `story_firestore_mapping` test: field missing, valid list, list with non-strings, more than 4 items.
- `chat_screen_test`: the keyword chips appear only when `keywords` is non-empty.
- `test/architecture_test.dart` needs no change: nothing new in the UI touches Firebase.

---

## 6. Moderation, privacy, minors

- Keywords are shown to every player of the room/language, children included, **before** the story is moderated. The child-safe instruction plus the blocked → `[]` handling is the safeguard. It's the same approach already used for titles of mature stories.
- Today the only unmoderated text shown to the next player is the last 5 words. Keywords summarize **the whole story so far**, so they mustn't amplify problematic content. That's why the instruction asks for neutral words or fewer keywords.
- Privacy: incomplete parts are now sent to Vertex AI after each part, not only completed stories. This is the same processor and the same purpose (automatic processing of user-written text), but the privacy policy should mention it. It's in the same pending privacy policy update as push notifications.

---

## 7. Cost and performance

- ≤ 3 calls per story to `gemini-3.1-flash-lite`, on a few hundred to ~2,000 input tokens and ~30 output tokens. That's negligible next to the existing review.
- Latency: a few seconds after the submit. It's asynchronous, so the player who submits doesn't wait.
- One more function invoked on every `stories` update (lock/unlock included). It exits at the first `if`, like the existing ones.

---

## 8. Rollout

1. Deploy `extractStoryKeywords` (backend first: old app versions ignore the new field).
2. Run the backfill in dry run, check the output on a sample, then `--write`.
3. Release the app version that shows the keywords (patch bump via the `commit-message` skill).
4. Update the privacy policy (§6).

There are no forced updates and no migration that breaks older clients.

---

## 9. Out of scope

- Using keywords for search or filters (they'd need an index and a different moderation level).
- Letting players edit or vote on keywords.
- Keywords on complete stories (they have the title).
- Notification text with keywords (notifications never contain unmoderated content; see `PUSH_NOTIFICATIONS_PLAN.md`).

---

## 10. Open decisions (defaults in bold)

Decided:
- **D1. Source text:** all parts so far. This changes the game's balance a bit: until now the next player knew only 5 words.
- **D2/D3. Where to show them:** only in the chat screen, as chips above the "story so far" bubble. The list doesn't change.

Still open:
- **D4. Stability across parts:** **regenerate all 4 every time** / pass the previous keywords to the model and ask it to keep them unless the story changed direction. The second is steadier but has a longer prompt; we can try it later if keywords jump around too much.
- **D5. Design pass:** **none**: one row of chips in the existing style is small enough to settle on device.
- **D6. Live update in chat:** **no (v1)** / `storyStream` in the repository so keywords appear while the screen is open (§5.2).

---

## 11. Tasks and estimates

| # | Owner | Task | Estimate |
|---|---|---|---|
| B1 | backend | Shared Gemini module, `keywords.ts` (trigger, extract, clean, save), tests | ~3h |
| B2 | backend | Backfill script, deploy, backfill run | ~1h |
| F1 | frontend | `Story.keywords` + mapping + tests | ~1h |
| F2 | frontend | Chat chips + l10n + widget tests | ~2h |
| D | Luca | Device check, privacy policy line, release | ~1h |

B1 and F1 can run in parallel. F2 can be tested with the fakes before the backend is deployed.

---

## 12. Implementation notes

What B1, B2, F1 and F2 did differently from, or in more detail than, the plan above:

- **Shared module:** `client()`, `MODEL`, `LANGUAGE_NAMES`, `DEFAULT_LANGUAGE` and `BLOCKED_FINISH_REASONS` moved to `functions/src/gemini.ts`; `reviewStory` is unchanged. The stale `lib/...` paths in the comments of `index.ts` now point at `lib/domain/models/story_language.dart`, `lib/domain/models/author_name.dart` and `lib/data/repositories/story/story_repository_firestore.dart`.
- **Exports:** `index.ts` re-exports `cleanKeywords`, `extractKeywords`, `keywordsPartCountFor` and `saveKeywords`, so the backfill script imports them from `lib/index.js`, which initializes the Admin app (same as `review-complete-stories.js`). The Firebase CLI deploys only the trigger.
- **Malformed responses:** besides network/API errors, `extractKeywords` throws when the JSON isn't parseable or has no `keywords` array, like `reviewStory` does. So a broken response keeps the previous keywords instead of overwriting them with `[]`. Only a blocked prompt or a safety finish reason saves `[]`.
- **`cleanKeywords`:** strips anything that isn't a letter or digit (Unicode-aware) at both ends, so `l'isola` keeps its inner apostrophe but `po'` would lose its final one. It also collapses inner whitespace, cuts at 24 code points (no split emoji or accented letters) and trims again after the cut. Empties don't count towards the 4.
- **`saveKeywords`** returns whether it wrote, and also skips a deleted story. The trigger ignores the result; the backfill reports stories "changed meanwhile".
- **Backfill:** it picks incomplete stories with ≥ 1 part and no `keywords` field. It also counts those skipped by `saveKeywords` in `--write` mode. It hasn't been run yet (rollout step 2).
- **Rules:** comment only. It also names `title`/`mature`, which are protected the same way.
- **App:** parsing is in `keywordsFromField` (public, in `story_firestore_mapping.dart`). It returns an unmodifiable list and doesn't trim or filter empty strings (the function already cleans them). `FakeStoryRepository` now keeps `keywords` across locks and submits (its `_copy` dropped them before), and that's tested in `test/testing/fake_story_repository_test.dart`. Its constructor already accepts any `Story`, so tests build stories with `keywords` directly.
- **Chat UI (F2):** the chips are a private `_StoryKeywords` widget in `chat_screen.dart`: a `Wrap` of Material `Chip`s (cream at 92% like `CreamCard`, ink bold 14 pt text, thin sage `primary` border, stadium shape, elevation 2, compact), padded by 10 to line up with `MessageBubble`. The group is a `Semantics` container labelled `storyKeywordsLabel`. It reads `story.keywords` straight from the `Story` the ViewModel holds, so `ChatViewModel` is unchanged, and it shows at most 4 chips even if a `Story` carries more. Widget tests are in `test/ui/chat/chat_screen_test.dart` (group `keywords`).
- **Chat UI, revised:** the chips were replaced by the turn card's "Di cosa parla finora" section (sage labels, visible heading, caption) in the writing screen redesign; see `docs/CHAT_SCREEN_UI_SPEC.md`.
