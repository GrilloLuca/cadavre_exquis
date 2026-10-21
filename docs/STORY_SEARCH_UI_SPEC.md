# Search completed stories: UI/UX spec

Status: ready to build (task U1 of `docs/STORY_SEARCH_PLAN.md`). Settles S2,
S3 and S4 and the UX questions §4.4 left to U1. Applies to
`CompleteStoriesScreen` (`lib/ui/complete_stories/widgets/complete_stories_screen.dart`)
plus one line in `HomeScreen`.

Wireframe: `docs/story_search_wireframe.svg` (A results, B no match in this
tab, C no match anywhere, D room without stories).

## 1. Goal

A user can type a word ("drago", "isola", "scuola") and see only the
completed stories of the current room whose **AI title or AI keywords**
match it. Both tabs are filtered at once. Matching rules are in the plan
(§2.2): folded case and accents, prefixes, every word must match. The UI adds
no new matching logic.

Out of scope: searching all rooms (S1), searching part text (S5), search
history or suggestions, `StoryReadScreen`, the gate flow (unchanged).

## 2. Decisions

| # | Question | Decision | Why |
|---|---|---|---|
| S2 | Field placement | **Inside `CompleteStoriesScreen`, above the `TabBar`, fixed** (does not scroll away). Shared by both tabs. Not in the Home AppBar. | The AppBar is shared by 3 home tabs. A field always in view tells the user the list is filtered. Tens of stories per room, so the 64dp it takes is cheap. |
| S3 | Tabs while searching | **Stay on the current tab. Both tab labels get the match count**, e.g. "Altre storie (2)" / "Le tue storie (1)". **No automatic tab switch.** When the current tab has no match but the other has some, its empty card offers a button that switches tab (section 6.2). | Jumping tabs while typing moves content under the user's finger. Counts and the button make the other tab's matches visible without surprise. |
| S4 | Keywords on tiles | **Yes, always** (also when not searching), as one line of plain text under the subtitle: `# castello · drago · nonna`. While searching, the keywords that match the query are **bold and `primaryDark`**. Hidden when a story has no keywords. Same on locked tiles. | Shows why a story matched (often a keyword, not the title), helps users pick a topic to search for, and keeps tile heights stable when typing starts. Keywords are generated child-safe (plan §2.1), so a locked tile shows nothing new that is unsafe. |
| — | Debounce | **None.** Filter on every `onChanged`. | In-memory filtering is microseconds (plan §7). |
| — | Query across room switch | **Cleared** when the room or language changes. | Switching room happens on the Profile tab, and rooms are in different languages, so an old query mostly gives "no results" in the new room and hides stories without the user noticing. **This changes plan §4.3 / F1** ("`setRoom` keeps the query"): `setRoom` must now reset it. See section 10. |
| — | Query across bottom-nav tab switch | **Kept** (the screen stays alive in the `IndexedStack`). | The user is coming back to the same search. |
| — | Text search on unlocked stories | No (plan S5). | — |

## 3. Layout (stories loaded, room has at least one completed story)

```
AppBar (HomeScreen, unchanged)
Column (stretch)
  Padding(LTRB 12, 12, 12, 4)
    SearchField                        ~48dp high
  TabBar                               48dp, labels with counts while searching
  Expanded
    TabBarView
      [Others]  list | per-tab empty card
      [Mine]    list | per-tab empty card
AdBanner + BottomNavigationBar (HomeScreen, unchanged)
```

- The field and the tab bar are only built in the loaded, non-empty branch.
  While `!isLoaded`: the spinner alone (unchanged). When the room has **no
  completed stories at all** (before filtering): the `noCompleteStories`
  card alone, with no field and no tabs (unchanged, panel D).
- "No stories at all" is decided on the **unfiltered** counts, never on the
  filtered sections. The ViewModel must expose them (section 10, `totalCounts`).
- If the unfiltered list becomes empty while a query is set (e.g. a minor
  verdict hides the room's only stories), the View clears the controller and
  calls `setQuery('')` together with dropping the field, so no invisible
  filter is left behind.

### 3.1 Search field

| Property | Value |
|---|---|
| Widget | `TextField`, `key: ValueKey('storySearchField')`, controller and `FocusNode` created in `initState` and disposed in `dispose` of the State |
| Decoration | `kTextFieldDecoration.copyWith(...)` (pill, 32 radius, `primaryDark` border 1dp / 2dp focused) with `filled: true`, `fillColor: AppColors.cream` (opaque, the background image must not show through) |
| Content padding | inherited `v10 h20`; with the 16sp text the field is ~48dp high |
| Prefix | `Icon(Icons.search, color: AppColors.primaryDark, size: 24)`, decorative (no semantics label) |
| Hint | `searchStoriesHint`, `maxLines: 1`, ellipsis, `hintStyle: TextStyle(color: AppColors.ink.withValues(alpha: 0.7))` (about 4.9:1 on cream) |
| Text | `TextStyle(color: AppColors.ink, fontSize: 16)`, `cursorColor: AppColors.primaryDark` |
| Suffix | clear button (3.2), only while `controller.text.isNotEmpty` (rebuild it with a `ValueListenableBuilder` on the controller, not the whole screen) |
| Keyboard | `textInputAction: TextInputAction.search`, `keyboardType: TextInputType.text`, `autocorrect: false` (it would turn "drag" into "drago" and back), `enableSuggestions: true`, `textCapitalization: TextCapitalization.none`, `autofocus: false` |
| Length | `inputFormatters: [LengthLimitingTextInputFormatter(50)]` (no visible counter) |
| `onChanged` | `_viewModel.setQuery(text)`, then jump both list controllers to offset 0 if they have clients, so results always start at the top |
| `onSubmitted` | unfocus only (results are already live; the action button just closes the keyboard) |
| `onTapOutside` | unfocus |

### 3.2 Clear button

- `IconButton(key: ValueKey('storySearchClear'), icon: Icon(Icons.close), color: AppColors.ink, tooltip: l10n.clearSearch)`. The default `IconButton` gives a **48x48dp** target; do not shrink it with `visualDensity` or constraints.
- Tap: `controller.clear()`, `_viewModel.setQuery('')`, jump lists to 0. **Focus does not change**: if the keyboard was open it stays open (the user is likely to type again); if it was closed it stays closed.
- Shown for any non-empty text, whitespace included (the user must be able to clear stray spaces, even though a whitespace query doesn't filter).

### 3.3 Keyboard and focus

- Both `ListView`s: `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag`.
- Any tile tap (open, or start of the gate flow) unfocuses the field **first**, so returning from `StoryReadScreen` / `AgeCheckScreen` doesn't pop the keyboard back up.
- Switching tab in the `TabBar` or via the 6.2 button keeps the focus as it is.
- `HomeScreen` bottom navigation `onTap`: unfocus (`FocusManager.instance.primaryFocus?.unfocus()`) before switching, so the keyboard doesn't stay open over another tab (the `IndexedStack` keeps the field alive).
- With the keyboard open on a 360x640dp phone, at least one full tile stays visible below the tab bar, and there's no blank gap from a doubled bottom inset (the screen has its own `Scaffold` nested in `HomeScreen`'s). Verify on device.
- Hardware keyboard / web: Tab order is field → clear button → tab "Altre storie" → tab "Le tue storie" → tiles. Enter submits (unfocus). No Esc shortcut in v1.

## 4. Tab bar

| State | Labels |
|---|---|
| Not searching (`!isSearching`) | Unchanged: `otherStoriesTab`, `yourStoriesHeading` |
| Searching | `storiesTabCount(label, count)` → "Altre storie (2)", "Le tue storie (0)", where `count` is the length of that tab's **filtered** section |

- Each tab: `Tab(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis))`, so a large text scale truncates instead of overflowing. Colours/styles unchanged (`primaryDark` selected w700, `ink` unselected).
- The selected tab never changes because of the query. The first-load tab choice (`_onViewModelChanged`) is unchanged; it always runs with an empty query because the query is reset on room switch.

## 5. Story tile

All existing rules from `MATURE_INLINE_UI_SPEC.md` §3 still hold (as amended by the code: locked tiles show the child-safe AI title). Only the subtitle grows a second line.

### 5.1 Keyword line

```
leading | title (w600, max 2 lines)
        | subtitle line 1: existing text (authorsCount, or "Storia per adulti · 4 autori")
        | subtitle line 2: [tag] castello · drago · nonna
```

| Property | Value |
|---|---|
| When | `story.keywords.isNotEmpty`, on normal, locked and unlocked tiles alike, searching or not |
| Structure | subtitle becomes `Column(crossAxisAlignment: start, mainAxisSize: min)` with the existing subtitle `Text`, `SizedBox(height: 4)`, then a `Row`: `Icon(Icons.tag, size: 14, color: AppColors.primaryDark)` (decorative, excluded from semantics), `SizedBox(width: 4)`, `Flexible(Text.rich(...))` |
| Text | keywords in stored order (max 4, already capped), joined by `" · "`, as stored (never translated, never re-cased). 13sp, `AppColors.ink`, w400, `maxLines: 2`, ellipsis |
| Highlight | while `isSearching`, a keyword that matches the query is a `TextSpan` with `fontWeight: w700, color: AppColors.primaryDark`. The rest stays ink w400. Weight differs, so it isn't conveyed by colour alone. Not searching: no highlight |
| Which keyword matches | decided by the domain, not the View: `StoryQuery.highlights(String keyword)` (section 10) |
| Title highlight | none (the title is already visible; keep it simple) |
| `isThreeLine` | leave false; the tile grows with its content, the leading icon stays vertically centred |

The tile grows by ~20dp when it has keywords. Tiles without keywords
(legacy stories before the backfill, or a refused extraction) keep today's
height. That mix is accepted.

### 5.2 Locked tile found by search

- Same as a locked tile today: padlock, AI title (or "Storia per adulti" when null), "Storia per adulti · N autori", plus the keyword line. **Never** any part text, searching or not.
- Tap: unfocus, then the existing gate flow, unchanged (spinner in trailing, snackbars, `AgeCheckScreen`).
- After an adult verdict the results stay filtered by the same query; matching mature tiles switch to the unlocked state in place.
- After a minor verdict, mature tiles disappear from the results and the counts drop accordingly.

## 6. States

Order of precedence per tab body, evaluated on every build:

| # | Condition | Tab body |
|---|---|---|
| 1 | `!isLoaded` | (whole screen) spinner, no field. Unchanged |
| 2 | unfiltered `mine + others == 0` | (whole screen) `noCompleteStories` card, no field, no tabs. Unchanged |
| 3 | this tab's unfiltered count is 0 | existing `noOtherCompleteStories` / `noYourCompleteStories` card, **even while searching** (the user has no stories there, a "no match" message would mislead) |
| 4 | searching, this tab has 0 matches, the other tab has ≥ 1 | 6.2 card |
| 5 | searching, both tabs have 0 matches | 6.3 card (same in both tabs) |
| 6 | otherwise | the (filtered) list |

### 6.1 Empty card layout

All cards reuse `_buildEmpty`'s frame: centred, `Padding(all 24)`,
`CreamCard(padding: h20 v16)`, text `AppColors.ink`, `TextAlign.center`.
Cards with an action are a `Column(mainAxisSize: min)`: message, then
`SizedBox(height: 8)` and a `TextButton` (`foregroundColor: AppColors.primaryDark`,
label w700, label may wrap to 2 lines, centred). `TextButton` already gives a
48dp minimum height.

The message `Text` of 6.2 and 6.3 is wrapped in `Semantics(liveRegion: true)`
so TalkBack/VoiceOver announce it when it appears while typing.

The query shown in messages is `query.trim()` with inner runs of whitespace
collapsed to one space (max 50 characters, by the input limit).

### 6.2 No match in this tab, matches in the other (panel B)

- Message: `noMatchingStoriesHere(query)` → "Nessuna storia trovata qui per «pirata»."
- Button: `showMatchesInTab(count, tab)` → "Vedi 1 storia in «Le tue storie»", where `tab` is the other tab's plain label (`otherStoriesTab` or `yourStoriesHeading`) and `count` its match count. Tap: `_tabs.animateTo(otherIndex)`. Focus unchanged.

### 6.3 No match anywhere (panel C)

- Message: `noMatchingStories(query)` → "Nessuna storia trovata per «draghi»."
- Second paragraph (`SizedBox(height: 8)` above, 14sp): `noMatchingStoriesHint` → "Prova con un'altra parola, oppure scrivila al singolare." (keywords are singular base forms, plan §2.2).
- Button: `clearSearch` → "Cancella ricerca". Same effect as the clear button (3.2), and it does not move focus to the field.

### 6.4 Whitespace or empty query

`isSearching == false`: no counts, no highlight, full lists. The clear
button still shows if the text has spaces.

### 6.5 Live updates while searching

A story completed or reviewed while the user searches appears (or not)
according to the same query; counts update. No toast, no scroll jump (only
the user's own typing jumps the lists to the top).

## 7. Accessibility

| Item | Requirement |
|---|---|
| Field name | The field is announced as "Cerca storie" (`searchStoriesLabel`) + its value or hint + "campo di testo / edit box", **whether or not it has text** (a hint alone disappears once text is typed). E.g. `Semantics(label: l10n.searchStoriesLabel, child: TextField(...))`; check that the label is not read twice. |
| Prefix icon | decorative, no semantics |
| Clear button | `tooltip: clearSearch` gives the label "Cancella ricerca, pulsante". 48x48dp target. |
| Tab labels | read with their count while searching ("Altre storie (2), scheda 1 di 2"). |
| Keyword line | `Text.rich(..., semanticsLabel: l10n.storyKeywordsSemantics(keywords.join(', ')))` → "Argomenti: castello, drago, nonna". The `Icons.tag` is excluded. The tile still merges into one node: "<title>, 4 autori, Argomenti: castello, drago, nonna". |
| Locked tile | unchanged semantics (button, "bloccata", hint "sbloccare"), plus the keyword sentence. |
| No-match cards | message in a live region (6.1); the action is a normal button. |
| Focus order | field → clear → tabs → list (or empty card and its button). Nothing autofocuses. After a pushed route pops, focus returns to the tapped tile (the field was unfocused before the push). |
| Touch targets | field ≥ 48dp high, clear button 48x48, card `TextButton`s ≥ 48dp high, tiles ≥ 56dp (unchanged). |
| Contrast (on cream #F4EEDA) | input text ink ~11.8:1; hint ink@70% ~4.9:1; `primaryDark` border/icons/highlight ~6.6:1; keyword ink ~11.8:1. All ≥ 4.5:1 for text, ≥ 3:1 for the field border. |
| Text scale 2.0 | field hint ellipsizes on one line; typed text scrolls horizontally; tab labels ellipsize; keyword line wraps to 2 lines then ellipsizes; card text wraps. |
| Dark mode | N/A (light-only app). |

## 8. Copy / l10n

Add to `lib/l10n/app_it.arb` (template, with `@` descriptions and
placeholders) and `lib/l10n/app_en.arb`, then `flutter gen-l10n`.

| Key | it | en |
|---|---|---|
| `searchStoriesHint` | Cerca per titolo o argomento | Search by title or topic |
| `searchStoriesLabel` | Cerca storie | Search stories |
| `clearSearch` | Cancella ricerca | Clear search |
| `storiesTabCount` | {label} ({count}) | {label} ({count}) |
| `noMatchingStories` | Nessuna storia trovata per «{query}». | No stories found for “{query}”. |
| `noMatchingStoriesHere` | Nessuna storia trovata qui per «{query}». | No stories found here for “{query}”. |
| `noMatchingStoriesHint` | Prova con un'altra parola, oppure scrivila al singolare. | Try another word, or write it in the singular. |
| `showMatchesInTab` | {count, plural, one{Vedi 1 storia in «{tab}»} other{Vedi {count} storie in «{tab}»}} | {count, plural, one{See 1 story in “{tab}”} other{See {count} stories in “{tab}”}} |
| `storyKeywordsSemantics` | Argomenti: {keywords} | Topics: {keywords} |

Placeholders: `label` String, `count` int, `query` String, `tab` String,
`keywords` String. Suggested `@` descriptions:

- `searchStoriesHint`: "Hint of the search field above the tabs of the Complete screen. Matches AI titles and keywords."
- `searchStoriesLabel`: "Screen-reader name of the completed-stories search field."
- `clearSearch`: "Tooltip of the clear (X) button in the search field, and label of the button in the no-results card."
- `storiesTabCount`: "Tab label while searching: the tab name (otherStoriesTab or yourStoriesHeading) and how many stories in it match."
- `noMatchingStories`: "No completed story in either tab matches the search; query is what the user typed."
- `noMatchingStoriesHere`: "The current tab has no match but the other tab has some."
- `noMatchingStoriesHint`: "Below noMatchingStories. Keywords are stored as singular nouns, so the singular often helps."
- `showMatchesInTab`: "Button switching to the other tab, which has count matching stories; tab is that tab's name."
- `storyKeywordsSemantics`: "Screen-reader text of the keyword line on a story tile; keywords is the story's keywords joined by ', '. The keywords are story content and are not translated."

Unchanged and reused: `noCompleteStories`, `noOtherCompleteStories`,
`noYourCompleteStories`, `otherStoriesTab`, `yourStoriesHeading`,
`authorsCount`, `matureStoryLockedTitle` and the other mature keys.
The plan's draft key `clearSearchTooltip` is replaced by `clearSearch`
(also used as a button label).

## 9. Edge cases

- **Query of short words only** ("re", "il"): filters with them (plan §2.2); UI behaves like any query.
- **Story with no title and no keywords:** never matches a non-empty query; with an empty query it shows as today (preview title, no keyword line).
- **Unlocked story with no title:** the title is the first-part preview (unchanged); it can't be matched by that text.
- **Room switch while a query is set:** the controller is cleared, the ViewModel resets the query, the spinner shows, the new room opens unfiltered with the usual first-load tab choice.
- **The screen is hidden (another bottom tab) while searching:** query, results and tab stay as they were when the user comes back; the keyboard is closed.
- **Paste of a long text:** cut at 50 characters by the formatter.
- **Rotating / resizing:** the field stays above the tabs; nothing is reset.

## 10. Changes this spec requires outside the View (for F1/B3)

1. **`CompleteStoriesViewModel.setRoom` resets the query** (`_query` back to empty) when the room actually changes. The F1 criterion and test "the query survives `setRoom`" become "**`setRoom` to a different room clears the query; `setRoom` to the same room keeps it**". The View also calls `controller.clear()` in `didUpdateWidget` when `language` or `roomId` differs from `oldWidget`.
2. **`CompleteStoriesViewModel.totalCounts`** → `({int mine, int others})`: the section sizes **after the mature filtering and before the query**. Used for states 2 and 3 (section 6). Must never count stories hidden from minors or during the birth-year load.
3. **`StoryQuery.highlights(String keyword)`** (B3, pure Dart): true when the query is non-empty and at least one effective query token is a prefix of a token of `keyword` (same folding and short-token rule as `matches`). Unit-tested with the `matches` cases.

## 11. Acceptance criteria

Widget tests (`test/ui/complete_stories/`) use `FakeStoryRepository` with stories built with `title` / `keywords`.

1. With at least one completed story, a `TextField` with key `storySearchField` is shown above the `TabBar`, with hint "Cerca per titolo o argomento" (it) / "Search by title or topic" (en). While loading, and when the room has no completed stories, there is no search field and no `TabBar`; the latter shows `noCompleteStories`.
2. Typing a word filters **both** tabs on the same frame (no debounce: one `pump()` after `enterText` is enough), keeping newest-first order; matches by title and by keyword both appear.
3. While searching, the tab labels read "Altre storie (n)" and "Le tue storie (m)" with the filtered counts; with an empty or whitespace query they have no count. The selected tab never changes because of typing.
4. The clear button (key `storySearchClear`, tooltip "Cancella ricerca") is absent with empty text, present with any text, has a ≥ 48x48dp tap area, and on tap empties the field and restores the full lists without changing focus.
5. Current tab 0 matches, other tab ≥ 1: the card shows "Nessuna storia trovata qui per «q»." and a button "Vedi N storia/storie in «<other tab>»" that selects the other tab.
6. Both tabs 0 matches: both show "Nessuna storia trovata per «q».", the singular hint, and a "Cancella ricerca" button that clears the search.
7. A tab with no stories at all keeps its existing empty message while searching (`noYourCompleteStories` / `noOtherCompleteStories`), not a no-match message.
8. A story with keywords shows them on its tile joined by " · ", also when not searching; a story without keywords has no keyword line. While searching, the matching keyword's `TextSpan` is w700 `primaryDark` and the others are not.
9. A locked tile found by a keyword shows the AI title (or "Storia per adulti"), "Storia per adulti · N autori" and the keywords, and **no part text** (test: `find.text(<part text>)` and `find.textContaining(<part text>)` find nothing). Tapping it runs the gate flow exactly as without search (`mature_story_lock_test.dart` passes unchanged).
10. Known minor / birth year loading: a query matching only a mature story's keyword gives the "no match anywhere" card (or `noCompleteStories` when the room only has that story), never the mature tile.
11. Submitting from the keyboard (`TextInputAction.search`) unfocuses the field and leaves the results as they are. Dragging a list closes the keyboard. Tapping a tile unfocuses the field before navigating.
12. Changing `language` or `roomId` empties the field and shows the new room unfiltered. Switching bottom tab and back keeps the query and results.
13. Semantics: the field exposes the label "Cerca storie" with and without text; the keyword line is read "Argomenti: a, b, c"; the no-match message is a live region.
14. The nine l10n keys exist in it and en with the strings in section 8; no user-visible string is hard-coded. `flutter gen-l10n`, `flutter analyze` and the full `flutter test` are clean.
15. Device check (manual, rollout step 3): field and results readable on a 360x640dp phone with the keyboard open (at least one tile visible, no doubled inset), and the ad banner is unaffected.
