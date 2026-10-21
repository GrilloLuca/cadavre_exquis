# Search completed stories by keyword: technical analysis

**User story.** As a user, I want to search for completed stories by keyword so I can find my favourite topic.

**Status:** proposed (2026-10-21), not started. Target: Android + iOS (web gets it for free: it's client-side filtering plus one Cloud Function change).

**Summary of the decisions:**
- **v1 searches on the device**, in the completed stories the screen already streams. That costs no extra Firestore reads, needs no index and no new field, and can't show anything the list doesn't already show.
- It matches the **AI title + AI keywords** only, never the part text. These are the two fields generated child-safe, so a match on a locked mature story reveals nothing that isn't already safe to show.
- **Backend:** completed stories get **final keywords** (from all 4 parts) through the existing `extractStoryKeywords` trigger, which today stops before the last part. A backfill covers the existing completed stories.
- **No paging in v1.** Server-side search (`searchTerms` + `array-contains`) and cursor paging are designed in §6 but deferred until the volume needs them. §6.1 has the triggers.

---

## 1. Current state (facts from the code)

- **Loading.** `StoryRepository.completeStoriesStream({language, roomId})` is a real-time `snapshots()` listener on `status == 'complete'` + room filter + `mature in [false, true]`, with **no `limit`, no `orderBy` and no paging**. It's sorted client-side by `Story.compareByCompletedAtDesc` (last part timestamp). Every app start reads every reviewed completed story of the room.
- **ViewModel.** `CompleteStoriesViewModel` keeps the whole list in `_all`. `sections` filters and splits it in one pass:
  - mature stories are dropped while the stored birth year is still loading (`!_birthYearLoaded`) and for known minors (`_isKnownMinor`);
  - the rest is split into `mine` (`hasPartBy(email)`) and `others`.
- **"Your stories" tab (c7def0e).** This is purely a View change. `CompleteStoriesScreen` shows `others` / `mine` in a `TabBar`, each tab with its own `ScrollController` and `PageStorageKey`. It opens on "Your stories" when only that tab has stories (`_onViewModelChanged`, on first load). Both tabs come from the same stream: "mine" can't be queried in Firestore (parts are an array of maps; see `anonymizeDeletedUser`: "Parts can't be queried by author").
- **Locked tiles show the AI title.** `_buildStoryCard` shows `story.title` on a locked tile (falling back to "Storia per adulti") and never the part text. This differs from MATURE_INLINE_PLAN D3 ("no title"): the review prompt was later made to always produce a child-safe title (`REVIEW_INSTRUCTION`, and `review-complete-stories.js --mature-titles` re-titled the old ones).
- **Keywords.** `extractStoryKeywords` runs after every part **except the last** (`keywordsPartCountFor` requires `after.status === "incomplete"`), and `saveKeywords` refuses non-incomplete stories. So:
  - stories completed after 2026-10-15 keep the keywords of their **first 3 parts** (`keywordsPartCount: 3`);
  - stories completed before that have **no `keywords` field** (the backfill only covered incomplete stories);
  - keywords are generated with the same child-safe bar as titles;
  - `Story.keywords` is already mapped in the app (`keywordsFromField`).
- **Rules.** `keywords`/`keywordsPartCount`/`title`/`mature` can't be written by clients (`hasOnly` lists). Every signed-in user can read every story; the age gate is app-side.
- **Volume.** At the last backfills: about 14 stories in total, 8 completed (2026-10-10). That's 5 language rooms plus private rooms, so a room has tens of completed stories at most for the foreseeable future.

---

## 2. Option analysis: where the search runs

| | (a) Client-side filter of the loaded list | (b) Firestore `array-contains` on normalized tokens | (c) External search (Algolia / Typesense / Vertex AI Search) | (d) Title prefix query |
|---|---|---|---|---|
| Extra reads per search | 0 | 1 per result | 0 Firestore, but paid per search/record | 1 per result |
| Backend work | none (beyond §3 keywords) | new `searchTerms` field, function, backfill, composite index with `arrayConfig` | extension + sync function, API keys, second datastore | index on `title` |
| Accents / case / plurals | any normalization in Dart, changeable in an app release | normalization fixed at write time, must match exactly in TS and Dart; only exact tokens (prefixes have to be stored explicitly) | best (typo tolerance, stemming per language) | case- and accent-sensitive, only the **start** of the title |
| Mature / minors | inherits `sections` filtering, can't leak | server can filter `mature == false` for known minors | the `mature` and room filters must be replicated in the index; one more place to leak | as (b) |
| Works with today's ordering | yes | needs a server `completedAt` to `orderBy` + page | own ranking | conflicts: inequality on `title` forces `orderBy title` first |
| Privacy | nothing new | nothing new | new data processor (story text leaves Google), privacy policy + Data safety update | nothing new |
| Fits until | the full list stops being cheap to stream (§6.1) | thousands of stories per room | any scale | never fits "by topic" |

**Recommendation: (a) now, with (b) as the documented next step (§6).**
- **Why (a):** the screen already holds the complete list of the room in memory, so filtering it is free, instant (no debounce, no spinner, works offline) and can't drift from what the list shows. The real scaling limit is the unpaged stream itself, not search. When that has to change, search has to move server-side at the same time (§6), because client-side search over a paged list would only search the loaded pages.
- **Rejected (c):** cost, a second datastore to keep in sync, a new processor for children's text, and the mature filter replicated outside Firestore. All of that for under 100 documents per room.
- **Rejected (d):** it only matches titles that *start* with the query, it's case- and accent-sensitive, it ignores keywords, and it fights the newest-first order.

### 2.1 What is searched: title + keywords, not the text

- The title and keywords are short, topical (characters, setting, situation) and generated **child-safe even for mature stories**. Matching a locked tile on them reveals nothing the tile doesn't already show, or isn't safe to show.
- The part text would leak for locked stories: a match on an explicit word tells an unverified user what's inside. It would also be noisy ("casa" matches half the stories), and it can't be carried over to (b) without indexing every word.
- Rejected alternative: search the text of unlocked stories only. Results for the same query would then change after the age check, and a mature story would match differently from a normal one. Not worth the inconsistency in v1 (open decision S5).

### 2.2 Matching rules (pure Dart, `lib/domain/models/story_search.dart`)

**Normalize** both the query and the story's title and keywords:
1. Lowercase.
2. Fold accents with an explicit map for the 5 room languages: `à á â ã ä å → a`, `æ → ae`, `ç → c`, `è é ê ë → e`, `ì í î ï → i`, `ñ → n`, `ò ó ô õ ö ø → o`, `œ → oe`, `ù ú û ü → u`, `ý ÿ → y`, `ß → ss`. Dart core has no NFD, and a package isn't worth it for this.
3. Split on anything that isn't a letter or digit (`RegExp(r'[^\p{L}\p{N}]+', unicode: true)`). So `l'isola` gives `l`, `isola`, and `castello-fantasma` gives two tokens.

**Match:**
- A story matches if **every** query token is a **prefix** of at least one story token (AND).
- Query tokens shorter than 3 characters are ignored when the query has at least one longer token. This drops articles like "il", "la", "un", "of" and "l'" without stopword lists. A query made only of short tokens uses them all.
- An empty or whitespace-only query matches everything, and the list is unfiltered.

**Language:**
- A room is single-language (`StoryLanguage`), so there's no cross-language concern.
- Prefix matching covers typing in progress and many inflections (`drag` → `drago`, `draghi`; `princip` → `principe`, `principessa`).
- Known limit: `draghi` doesn't find `drago`. Mitigation: the keyword prompt asks for **singular base forms** (§3.2), so typing the singular works best. Stemming per language is rejected (5 languages, little gain at this size).

**Order:** results keep the list's order (newest completed first). There's no relevance ranking: with a few matches per room, it's predictable and enough.

---

## 3. Backend changes (functions/)

### 3.1 Final keywords on completion: extend the existing trigger
Completed stories need keywords that describe the **whole** story (the epilogue included), and the legacy ones need any at all. We reuse the existing `keywords` / `keywordsPartCount` fields and the `extractStoryKeywords` trigger. We don't add a new field or a new function.

- `keywordsPartCountFor(before, after)`: drop the `after.status !== "incomplete"` condition. It returns `n` whenever exactly one part was added, so it now also fires on the completing submit (n = 4). Lock changes, the review write and the keywords write still exit (the part count doesn't change).
- `saveKeywords(storyId, partCount, keywords)`: accept `status` `incomplete` **or** `complete`. Keep the other guards (`parts.length === partCount`, stored `keywordsPartCount < partCount`). The write stays transactional and idempotent.
- `KEYWORDS_INSTRUCTION`: today it says "the beginning of a short story... so the next player knows what the story is about". Make it hold for both cases: "a short story, possibly unfinished... capture its characters, setting and situation". Add "**prefer singular nouns in their base form**" (helps prefix search, harmless in the chat).
- Keep the child-safe sentence unchanged: keywords of a mature story are searchable and may be shown by everyone.
- Why not fold keywords into `reviewStory`: one call would be cheaper, but a malformed keywords answer would then fail the review and **hide the story** (no `mature`). Keeping them separate also keeps `reviewCompletedStory` and its notification untouched. The cost is one extra flash-lite call per completed story, which is negligible.
- Effect in the app: none outside search. The chat never opens a completed story, `StoryReadScreen` doesn't show keywords, and notifications don't use them.
- Ordering race: `reviewCompletedStory` and `extractStoryKeywords` both fire on the completing update and write different fields in separate transactions, so they don't conflict. Each write re-triggers both functions, and both exit early.

### 3.2 Backfill: `functions/scripts/extract-incomplete-keywords.js --complete`
Add a `--complete` mode to the existing script, rather than a third script:
- Targets: `status == 'complete'` stories where `keywordsPartCount !== parts.length` (missing field or stale 3-part keywords).
- It calls `extractKeywords` / `saveKeywords(doc.id, parts.length, ...)` directly, with a dry run by default and `--write` to save. It reports the counts, like today.
- It's idempotent: a re-run finds 0 candidates.
- Update the script's header comment and the comment at the top of `keywords.ts`.

### 3.3 Rules, indexes
- **Rules:** no change. The clients still can't write `keywords`. Update the `isValidSubmit` comment ("written by extractStoryKeywords, also on completion").
- **Indexes:** no change in v1. `firestore.indexes.json` stays as is.

### 3.4 Function tests (`functions/test/keywords.test.js`)
- `keywordsPartCountFor`: 3→4 parts with `status: complete` now returns 4. Lock change, review write (`title`/`mature` only) and keywords write still return `undefined`. Legacy docs without `parts` still return `undefined`.
- `saveKeywords` isn't unit-tested today (Admin SDK). Keep its guards as pure checks if it's easy to extract them; otherwise check it on the emulator or in production after deploy (B2).

---

## 4. App (Flutter, MVVM)

### 4.1 Domain: `lib/domain/models/story_search.dart` (new, pure Dart)
- `String foldForSearch(String text)`: lowercase + accent fold (§2.2).
- `List<String> searchTokens(String text)`: fold + split, empties dropped.
- `class StoryQuery`: built from the raw query once per change. It holds the effective tokens (short-token rule) and `isEmpty`, and has `bool matches(Story story)`, which checks against `searchTokens` of `story.title ?? ''` plus every `story.keywords` entry.
- No Flutter, no SDK, so `architecture_test.dart` stays green. Unit tests in `test/domain/models/story_search_test.dart`.

### 4.2 Data layer
- **Repository interface:** no change. Search filters what `completeStoriesStream` already returns.
- **`Story` / mapping:** no change. `keywords` is already mapped and capped at 4; `title` already exists.
- **`FakeStoryRepository`:** no change. Tests build stories with `title`/`keywords` directly.

### 4.3 ViewModel: `CompleteStoriesViewModel`
- New state: `StoryQuery _query` (empty by default), getter `String get query` (the raw text), `bool get isSearching` (`!_query.isEmpty`).
- New method `void setQuery(String text)`: rebuilds `_query` and calls `notifyListeners()` only if the effective tokens changed. It's a plain synchronous setter like `setRoom`, not a `Command`: there's no async work, no error and nothing to run twice.
- `sections` applies `_query.matches(story)` **after** the existing mature filtering, in the same single pass. So a hidden mature story (birth year loading, known minor) can never come back through search.
- `setRoom` keeps the query: the View owns the `TextEditingController`, and the user is still looking for the same topic.
- `isLoaded` doesn't change. The View tells "no stories at all" from "no matches" with `isSearching`.
- Tab selection: `_onViewModelChanged` picks the initial tab on first load only. Search doesn't switch tabs automatically (U1 can decide otherwise, see S3).

### 4.4 View: `CompleteStoriesScreen` (shape decided by U1)
- A search field owned by the View (`TextEditingController`, `onChanged: _viewModel.setQuery`, clear button). No debounce: filtering is in memory.
- The search is shared by both tabs. Each tab shows its filtered list or a "no matches" message. When the room has no completed stories at all, the single `noCompleteStories` card stays and there's no search field.
- Locked tiles keep their current content and gate flow. A search doesn't unlock anything.
- New l10n keys in `app_it.arb` (template) and `app_en.arb`, then `flutter gen-l10n`. Draft:
  - `searchStoriesHint`: "Cerca per titolo o parola chiave" / "Search by title or keyword"
  - `noMatchingStories`: "Nessuna storia trovata per «{query}»" / "No stories found for “{query}”"
  - `clearSearchTooltip`: "Cancella ricerca" / "Clear search"
  - final wording by U1

### 4.5 Tests
- `test/domain/models/story_search_test.dart`:
  - accent folding (`città` ↔ `citta`, `Müller` ↔ `muller`, `straße` ↔ `strasse`);
  - case;
  - apostrophes (`l'isola` found by `isola`);
  - prefix (`drag` finds `drago`);
  - AND of tokens;
  - the short-token rule (`il drago` finds a story titled "Un drago a Milano"; `re` alone still filters);
  - empty or whitespace query;
  - story with no title and no keywords (only an empty query matches);
  - keywords matched as well as the title.
- `test/ui/complete_stories/complete_stories_view_model_test.dart`:
  - `setQuery` filters both `mine` and `others`, keeping the order;
  - clearing restores the full list;
  - no notify when the effective query doesn't change;
  - the query survives `setRoom`;
  - **known minor: a query matching only a mature story's keyword gives empty sections**;
  - while the birth year is loading, mature stories don't match;
  - unknown age: the matching mature story is returned, and `isLocked` is still true.
- Widget tests (`test/ui/complete_stories/`):
  - typing filters the visible tiles in both tabs;
  - the "no matches" text shows with the query;
  - the clear button restores the list;
  - a locked tile found by search still runs the gate flow and shows no part text;
  - with no completed stories, there's no search field and `noCompleteStories` shows.

---

## 5. Mature content and minors (acceptance-critical)

| User | What search can return |
|---|---|
| Known minor (stored minor year or session minor verdict) | Never a mature story: they are removed before matching |
| Birth year still loading | Never a mature story (same rule as the list) |
| Unknown age | Mature stories as **locked** tiles, matched on child-safe title/keywords only, never on text |
| Session adult | Everything, unlocked |

The residual risk is the same as today: mature documents still reach every device (MATURE_INLINE_PLAN, Risk 1). Search adds no new exposure. Any future server-side search (§6) must keep matching on title/keywords only, and should filter `mature == false` in the query for known minors.

---

## 6. Later: paging and server-side search (designed, not scheduled)

### 6.1 When to do it
Do it when any of these happens:
- a room has more than about 200 reviewed completed stories;
- the Firestore console shows the complete-list reads driving cost (each app start reads N documents per user, plus one per change);
- the first load of the complete tab feels slow on device.

Until then, paging would add cursor state, two loading modes and a worse search (it only finds loaded pages) for no benefit.

### 6.2 Shape
- **`completedAt`** (server timestamp): written by `saveReview` together with `mature`, backfilled from the last part's timestamp. Queries can then `orderBy('completedAt', descending)` without dropping legacy docs. It's Admin-only, so the rules don't change.
- **Paging:** the first page (`limit(30)`) stays a real-time listener, so new completions and late reviews appear. Older pages are one-shot `get()` with `startAfterDocument(last)`, appended on scroll. The repository grows a `fetchCompleteStoriesPage({language, roomId, after, limit})`, and the domain gets a cursor type that hides `DocumentSnapshot`.
- **`searchTerms`** (`string[]`): the folded tokens of title + keywords, plus their 3+ character prefixes (so `array-contains` can match prefixes), written by the same function that writes keywords/title. The query uses `array-contains` on the longest query token; the other tokens are filtered client-side on the page. The normalization is then duplicated in TS and Dart, so it needs a shared JSON fixture of test vectors used by both test suites.
- **Indexes:** `(status, language, roomId, mature, completedAt desc)` and `(status, roomId, mature, completedAt desc)` for paging, plus the same with `searchTerms` (`arrayConfig: CONTAINS`) before `completedAt` for search.
- **Minors:** known minors query `mature == false` instead of `in [false, true]`, so mature documents no longer even reach their devices. That's a small real improvement over today.
- **"Your stories" with paging:**
  - it can't come from the shared pages without gaps, so it would need an `authorEmails` array (Admin-written; it exposes nothing new, since emails are already in `parts`) and its own query;
  - Firestore allows only one `array-contains` per query, so "my stories matching X" filters `searchTerms` client-side over the user's own (few) stories;
  - this is the part that most argues for postponing §6.
- External search (option c) stays rejected unless a "search all rooms" feature appears.

---

## 7. Cost and performance (v1)

- **Firestore:** no extra reads. Search runs in memory over the list already streamed.
- **Gemini:** +1 `extractKeywords` call per completed story (flash-lite, a few hundred to ~2,000 input tokens, ~30 output tokens), plus one backfill call per existing completed story (tens). Negligible.
- **Device:** filtering tens to a few hundred stories × ~12 tokens per keystroke takes microseconds. Precompute the story tokens only if profiling says so.

---

## 8. Rollout

1. **[Luca, manual]** Deploy the function change: `firebase deploy --only functions:extractStoryKeywords` (backend first; old apps ignore it).
2. **[Luca, manual]** Backfill:
   - `cd functions && npm run build && gcloud auth application-default login`, then `node scripts/extract-incomplete-keywords.js --complete` (dry run);
   - check a sample of keywords (child-safe, singular, in the room's language), then run it again with `--write`;
   - a re-run of the dry run must report 0 candidates.
3. **[Luca, manual]** Device check: search in an Italian room and an English room, accents, a locked mature story, and an account with a stored minor birth year.
4. Commit with the `commit-message` skill (patch bump), then release. No rules or index deploy is needed. There's no privacy policy change: completed stories already go to Vertex AI for review.

Release order isn't constrained: an app shipped before the backfill still searches titles and whatever keywords exist.

---

## 9. Out of scope
- Searching the part text (S5), all rooms at once, or incomplete stories.
- Relevance ranking, typo tolerance, stemming, search history or suggestions.
- Paging and server-side search (§6, until §6.1 triggers).
- Showing keywords on the read screen (U1 may propose keywords on tiles, see S4).

---

## 10. Open decisions (defaults in bold)
- **S1. Search scope:** **current room only** (like the list) / all rooms. All rooms needs §6 anyway.
- **S2. Field placement:** **above the tab bar, shared by both tabs** / a search icon in the Home AppBar that expands. U1 decides; the AppBar lives in `HomeScreen` and is shared by 3 tabs, which argues for keeping it inside `CompleteStoriesScreen`.
- **S3. Tab behaviour while searching:** **stay on the current tab, with match counts in the tab labels** / jump to the tab that has matches. U1 decides.
- **S4. Show keywords on tiles:** without them a user can't tell why a story matched (the match may be a keyword, not the title). **U1 to propose**: e.g. the keywords in the subtitle, or only the matched one highlighted. It's safe on locked tiles too (child-safe keywords).
- **S5. Text search on unlocked stories:** **no** (§2.1).

---

## 11. Tasks

| # | Owner | Task | Estimate |
|---|---|---|---|
| B1 | backend-developer | Keywords on completion: trigger condition, `saveKeywords`, prompt, tests, comments | ~1.5h |
| B2 | backend-developer | `--complete` backfill mode | ~1h |
| B3 | backend-developer | Domain `story_search.dart` + unit tests | ~1.5h |
| U1 | ui-ux-designer | Search UX spec `docs/STORY_SEARCH_UI_SPEC.md` (+ wireframe) | ~2h |
| F1 | frontend-developer | `CompleteStoriesViewModel` query + tests | ~1.5h |
| F2 | frontend-developer | Search field, empty states, l10n, widget tests | ~3h |
| L | Luca (manual) | Deploy, backfill run, device check, commit, release | ~1h |

B1/B2, B3 and U1 can run in parallel. F1 needs B3. F2 needs F1 and U1. Rollout steps 1–2 (L) need B1/B2 merged locally, not the app.

### B1 (backend-developer): final keywords on completion
- Changes in `functions/src/keywords.ts`, as in §3.1; update the comments in `keywords.ts`, `index.ts` (`extractStoryKeywords`) and `firestore.rules` (comment only).
- Acceptance criteria:
  - `keywordsPartCountFor` returns 4 for the completing update (3→4 parts, `status: complete`), and `undefined` for lock changes, `title`/`mature` writes, `keywords` writes and docs without `parts` (tests in `functions/test/keywords.test.js`).
  - `saveKeywords` writes on a complete story when `parts.length === partCount` and the stored `keywordsPartCount` is missing or lower; it still refuses deleted stories, mismatched part counts and equal or higher stored counts.
  - The prompt says "possibly unfinished" and "prefer singular nouns", and the child-safe sentence is unchanged.
  - `reviewCompletedStory` and `notifications.ts` aren't modified.
  - `npm test` passes in `functions/`.

### B2 (backend-developer): backfill mode
- `--complete` flag in `functions/scripts/extract-incomplete-keywords.js`, as in §3.2, plus an updated usage header.
- Acceptance criteria:
  - The dry run lists each candidate's id and keywords and writes nothing.
  - `--write` saves through `saveKeywords` and reports written / skipped ("changed meanwhile") / failed counts.
  - The candidates are exactly the complete stories with `keywordsPartCount !== parts.length`.
  - A second run reports 0 candidates.
  - The incomplete mode (no flag) behaves as before.
- **Do not run against production**: that's step L.

### B3 (backend-developer): search domain helper
- `lib/domain/models/story_search.dart` as in §4.1, and `test/domain/models/story_search_test.dart` with the cases in §4.5.
- Acceptance criteria:
  - Pure Dart, no Flutter import.
  - Every matching rule in §2.2 is covered by a test.
  - `flutter analyze` is clean, and `flutter test` passes (including `architecture_test.dart`).

### U1 (ui-ux-designer): search UX
- Write `docs/STORY_SEARCH_UI_SPEC.md` (and optionally a wireframe SVG), in the style of `MATURE_INLINE_UI_SPEC.md`. Decide S2, S3 and S4.
- The spec covers:
  - placement and keyboard behaviour (search action, dismissing the keyboard on scroll);
  - the clear button;
  - the empty state when nothing matches, per tab and in total;
  - how a matched locked tile looks;
  - whether and how keywords show on tiles;
  - accessibility (semantics labels, a 48 dp touch target for the clear button);
  - final IT/EN strings.
- Constraints:
  - No part text is ever shown on a locked tile.
  - There's no search field when the room has no completed stories.
  - The design works within the existing cream/sage theme and the bottom ad banner.
- Acceptance criteria: every state in §4.4 has a described layout and final strings, and S2–S4 have a decision.

### F1 (frontend-developer): ViewModel
- Changes in `CompleteStoriesViewModel`, as in §4.3, with the tests in §4.5 (ViewModel part).
- Acceptance criteria:
  - The query filters both sections after the mature filtering.
  - Known minors and the birth-year-loading state never get mature stories from a query (dedicated tests).
  - No notification fires when the effective query is unchanged.
  - The query survives `setRoom`.
  - Unlock flow tests pass unchanged.

### F2 (frontend-developer): screen
- Changes in `CompleteStoriesScreen` per the U1 spec, the l10n keys in both `.arb` files and `flutter gen-l10n`, and the widget tests in §4.5.
- Acceptance criteria:
  - The widget tests listed in §4.5 pass.
  - The `TextEditingController` is created and disposed in the State.
  - The ViewModel is still created only in `initState`.
  - All user-visible text goes through `AppLocalizations` in IT and EN.
  - Existing `mature_story_lock_test.dart` and tab tests pass.
  - `flutter analyze` is clean, and the full `flutter test` passes.

---

## 12. Risks
1. **Keyword quality drives recall.** Stories with poor or few keywords (refused by the model → `[]`) are only found by title. That's accepted; the backfill dry run gives a quality sample.
2. **Plural/inflection misses** (`draghi` ≠ `drago`). Mitigated by prefix matching and the singular-noun prompt. If it shows up on device, revisit with a light per-language suffix strip.
3. **Unpaged stream growth.** Not created by search, but search makes the full list look like a feature, so moving to §6 means re-implementing search server-side. Watch the §6.1 triggers.
4. **Keyword trigger now runs on completion** alongside the review. It writes disjoint fields in separate transactions; any re-trigger exits early. Verify once in the logs after the deploy (no loop, one extraction per completion).
5. **Plan/code drift on locked titles.** MATURE_INLINE_PLAN says locked tiles hide the title; the code shows the child-safe AI title. Search relies on the title being child-safe, which is the current prompt. Any future change to that assumption must also revisit search.
