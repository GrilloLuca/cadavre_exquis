# Writing screen ("chat screen"): UI/UX spec

Status: built (2026-10-15) with the decisions below; see "Implementation
notes" at the end for the deviations. Not yet checked on device.

**Owner decisions (2026-10-15), these override the rest of the spec:**
- **No "Remember" section** for now (too much text): drop row 8 of §4.2 and
  §4.4, and the keys `chatTipsHeading`, `chatTipTurns`, `chatTipHook`,
  `chatTipComplete`, `chatTipLength`, `chatTipLock`. The 5,000-character
  limit is still enforced by the field and its counter (§4.5).
- **Q1:** the keyboard does not open automatically.
- **Q2:** closing (X or back) with unsent, non-blank text asks for
  confirmation, with the 4 keys proposed in §12.
- **Q3:** the completed snackbar is neutral for every story:
  `chatCompletedSnackbar` = "Storia completata!" / "Story complete!".
- **Q4:** neutral Italian: `chatLeadFirst` = "Tocca a te iniziare: scegli tu
  personaggi, luogo e cosa succede." (English unchanged).
- **Q5:** moot (no tips).
Replaces the body and input bar of `ChatScreen`
(`lib/ui/chat/widgets/chat_screen.dart`). `ChatViewModel` is unchanged.

Wireframe: `docs/chat_screen_wireframe.svg`.

## 1. Goal

A player who opens a story must understand, without help:

1. **which part** they are writing, and where it sits in the story (2 of 4);
2. **what they know** about the story: the keywords (a summary) and the
   last 5 words (the exact point to continue from), and why that's all;
3. **what to do**: write a few sentences, end with a hook, press Send;
4. **what happens next**: the story goes to someone else, or is complete.

The screen reads top to bottom as **your turn → your context → write here →
send**. It stops looking like a chat.

Out of scope: data, repositories, Cloud Functions, `ChatViewModel`'s
commands, the lock rules, `NotificationOfferDialog`, the incomplete-stories
list. No more story text is shown than today: only the last 5 words of the
previous part (section 9 covers a long "word").

## 2. Diagnosis: what's confusing today

| # | Problem | Why it hurts |
|---|---|---|
| D1 | **Chat metaphor.** The last 5 words sit in a `MessageBubble` with a tail and a sender label ("Finora è stato scritto..."), above a one-line input bar with "Invia", like a messaging app. | It reads as a message from another person that you should *reply to*, not a sentence you must *continue*. A one-line bar suggests a short reply, not a paragraph. |
| D2 | **Keywords have no visible label.** Four elevated `Chip`s appear first, above everything. The label "Parole chiave" exists only for screen readers. | They look like tags, filters or buttons (Material chips look tappable). Nobody says they summarize the *whole* story, or how they differ from the 5 words. |
| D3 | **Wrong hierarchy.** The chips come first, the bubble second, the input last and detached at the bottom. Nothing connects the 5 words to the place where you type. | The key information (where to continue from) is neither first nor next to the input. |
| D4 | **Which part, and how far along?** Only the AppBar says "Sviluppo (1/2)". The hint repeats it in lower case ("Scrivi qui: sviluppo (1/2)..."). | "(1/2)" is jargon. There's no "part 2 of 4", so a new player can't tell they're in the middle and that 2 more players follow. |
| D5 | **Rules only for the first writer.** The `chatFirstWriterHint` (5 long bullets) shows only when there are no parts. Later players get no instructions. Writing the epilogue looks exactly like writing a middle part. | The "end with a hook" advice matters to every non-final writer. The epilogue writer must know they are ending the story. The first-writer card is a wall of text for a child. |
| D6 | **How long?** No guidance and no counter. The 5000-character limit exists only in `firestore.rules`, so going over it fails with "Si è verificato un errore. Riprova." | Kids don't know whether to write a word or a page. Going over the limit gives an error that doesn't say what to fix. |
| D7 | **After sending, nothing is said.** The screen just closes (after the notification offer, if any). | No confirmation that the part was saved, or of what happens now. Ending a story gets no reward. |
| D8 | **Locking and sending.** While the lock is taken, a bare spinner covers the screen. While sending, there's no progress at all: the field just turns grey. | The player can't tell if the app is working. Tapping close during the send races the submit with the unlock. |
| D9 | **Small phone with keyboard.** The keyboard opens automatically as soon as the lock is held. On 360x640 it covers about 260dp, so the context scrolls up out of view while you type. | You lose sight of the 5 words, the one thing you need while writing. |
| D10 | Small things: a double ellipsis ("Finora è stato scritto..." + `"...parole"`), straight quotes, and the field disabled-grey while locking. | Visual noise. |

## 3. Recommended design: "turn card + composer"

Two blocks, no bubbles:

1. **Turn card** (scrolls): a `CreamCard` that says which part this is,
   what to do, what the story is about (keywords), and a short "Remember"
   list.
2. **Composer** (docked at the bottom, always above the keyboard): it
   starts with **"Continua da qui: …ultime cinque parole"**, so the 5 words
   lead straight into the multi-line field. Below the field: counter (near
   the limit only) and a filled **Invia** button.

The 5 words are shown **once**, in the composer, right where the player
types. They stay visible with the keyboard open, which fixes D1, D3 and D9
together.

```
┌ AppBar (primary) ───────────────────────┐
│ ✕   Sviluppo (1/2)                      │
├─────────────────────────────────────────┤
│ ┌ CreamCard ──────────────────────────┐ │  scrolls
│ │ ▬▬ ▬▬ ▭▭ ▭▭   Parte 2 di 4          │ │
│ │ Continua la storia            (H)   │ │
│ │ Della storia vedi solo le ultime 5  │ │
│ │ parole: riparti da lì, …            │ │
│ │                                     │ │
│ │ DI COSA PARLA FINORA                │ │  only if keywords
│ │ (drago) (faro) (tempesta) (segreto) │ │
│ │ Parole scelte in automatico …       │ │
│ │                                     │ │
│ │ RICORDA                             │ │
│ │ • Il prossimo giocatore vedrà …     │ │
│ │ • Bastano poche frasi …             │ │
│ │ • Mentre scrivi, la storia è …      │ │
│ └─────────────────────────────────────┘ │
├══ composer (cream, 2dp primary top) ════┤  docked
│ Continua da qui:                        │  later parts only
│ …quando il faro si spense               │
│ ┌─────────────────────────────────────┐ │
│ │ Scrivi qui la tua parte…            │ │  3–6 lines
│ └─────────────────────────────────────┘ │
│ 4.612/5.000                 [➤ Invia]   │
└─────────────────────────────────────────┘
```

### Alternative (not recommended): single scrolling page

Everything in one `ListView`: the card, then the quote, then an inline
multi-line field, then a full-width Send button at the end. It's simpler
(no docked composer), but on a small phone with the keyboard open the quote
and the button scroll out of view, which brings D9 back. Keep it only if the
docked composer turns out awkward on device.

## 4. Screen structure and tokens

`Scaffold` > `Background(opacity: 0.2)` > `SafeArea(bottom: false)` >
`Column`: `Expanded(SingleChildScrollView(card))`, then the composer. The
scroll view uses `keyboardDismissBehavior: onDrag`.

### 4.1 AppBar (unchanged except while sending)

| Item | Spec |
|---|---|
| leading | `IconButton(Icons.close)`, tooltip `MaterialLocalizations.closeButtonTooltip`. **Disabled (`onPressed: null`) while `submit.running`**, see section 6.5. |
| title | `positionLabel(context, story.currentPosition)`, unchanged. |
| colours | `AppColors.primary` background, white foreground (theme). |

### 4.2 Turn card

`CreamCard(padding: EdgeInsets.all(16))`, outer padding of the scroll view
`EdgeInsets.fromLTRB(16, 16, 16, 16)`. A `Column(crossAxisAlignment: start)`
in this order:

| # | Element | Spec |
|---|---|---|
| 1 | **Progress row** | `Row`: 4 segments, each `Expanded`, height 6, radius 3, gap 6, max total width 160 (`ConstrainedBox`). Done parts: `AppColors.primary` fill. Current part: `AppColors.primaryDark` fill. Future parts: no fill, 1.5dp border in `AppColors.ink` at alpha 0.3. Then a gap of 12 and `chatPartProgress(current, total)`, 13sp, w600, `AppColors.ink` at alpha 0.75. `current` = `kStoryPositions.indexOf(story.currentPosition) + 1`, `total` = `kStoryPositions.length`. If the position is unknown (index -1), hide the whole row. The segments are `ExcludeSemantics`; the text carries the meaning. |
| 2 | gap 12 | |
| 3 | **Headline** | By position: `chatHeadlineFirst` (introduzione), `chatHeadlineMiddle` (sviluppo1/2), `chatHeadlineLast` (epilogo). 20sp, w600, `AppColors.ink`. `Semantics(header: true)`. |
| 4 | gap 6 | |
| 5 | **Lead** | `chatLeadFirst` / `chatLeadMiddle` / `chatLeadLast`. 15sp, height 1.4, `AppColors.ink`. |
| 6 | **Keywords section** | Only when `story.parts.isNotEmpty && story.keywords.isNotEmpty`. See 4.3. |
| 7 | gap 20 | |
| 8 | **Remember** | Subheading `chatTipsHeading`, 13sp, w700, `AppColors.primaryDark`, letter spacing 0.4, `Semantics(header: true)`; gap 8. Then the tips (4.4), each a `Row`: a 6dp `AppColors.primary` dot aligned to the first line (top padding 7), gap 10, `Expanded(Text)` 14sp, height 1.35, `AppColors.ink`. 8 between tips. |

### 4.3 Keywords section

| Element | Spec |
|---|---|
| gap above | 20 |
| Heading | `storyKeywordsLabel` (new value: "Di cosa parla finora"), same style as the Remember subheading. `Semantics(header: true)`. gap 8. |
| Tags | `Wrap(spacing: 8, runSpacing: 8)` of at most 4 (`take(4)`). Each tag is a **non-interactive** label, not a button: `Container` with `AppColors.sage` fill, `StadiumBorder`, padding h12 v6, text 14sp w600 `AppColors.ink`, `maxLines: 1`, ellipsis. No elevation, no border, no ripple. (A `Chip` with `elevation: 0`, `side: BorderSide.none`, `backgroundColor: AppColors.sage` is fine too, as long as it has no `onPressed`/`onSelected`.) |
| Caption | gap 8, `chatKeywordsCaption`, 13sp, `AppColors.ink` at alpha 0.75. |
| Semantics | Wrap heading + tags + caption in `Semantics(container: true)`. Each tag reads as its text. |

The sage tags on the cream card replace the elevated cream chips on the
background: inside the card they read as "labels about this story", not
as controls.

### 4.4 Tips by position

| Position | Tips, in order |
|---|---|
| introduzione | `chatTipTurns`, `chatTipHook`, `chatTipLength(5000)`, `chatTipLock` |
| sviluppo1, sviluppo2 | `chatTipHook`, `chatTipLength(5000)`, `chatTipLock` |
| epilogo | `chatTipComplete`, `chatTipLength(5000)`, `chatTipLock` |

The rules that used to live only in `chatFirstWriterHint` are now short
tips shown to whoever needs them.

### 4.5 Composer (docked)

`Container(decoration: kMessageContainerDecoration.copyWith(color: AppColors.cream))`
(keeps today's 2dp `AppColors.primary` top border), then `SafeArea(top: false)`,
padding `fromLTRB(16, 12, 16, 8)`. A `Column(crossAxisAlignment: stretch)`:

| # | Element | Spec |
|---|---|---|
| 0 | **Progress bar** | Only while `lock.running`: a `LinearProgressIndicator(minHeight: 2, color: AppColors.primary, backgroundColor: AppColors.sage)` laid over the top border (e.g. `Stack` at top, or replacing the border while running). |
| 1 | **Lead-in** | Only when `story.parts.isNotEmpty`. `chatContinueFromLabel`, 13sp, w700, `AppColors.primaryDark`; gap 2; then `chatLastWords(words)`: 17sp, w500, **italic**, height 1.3, `AppColors.ink`, `maxLines: 3`, ellipsis (see section 9 for a long word). Wrap both in `MergeSemantics`. gap 10. |
| 2 | **Field** | `TextField`, `keyboardType: multiline`, `textCapitalization: sentences`, `minLines: 3`, `maxLines: 6` (4 while the keyboard is open, i.e. `MediaQuery.viewInsetsOf(context).bottom > 0`). `maxLength: 5000`, `maxLengthEnforcement: enforced`. Decoration: `hintText: chatInputHint` (ink at alpha 0.6), `contentPadding: all(12)`, `OutlineInputBorder(radius 12)` with `AppColors.primaryDark` 1dp enabled, 2dp focused, `AppColors.ink` alpha 0.3 1dp disabled. No fill (sits on the cream composer). Text 16sp, height 1.4, `AppColors.ink`. `Semantics(label: chatInputLabel(position))` around it (the hint vanishes once text is typed). The default counter is hidden (`buildCounter` returns `null`); the counter lives in the footer. |
| 3 | gap 8 | |
| 4 | **Footer** | `Row`: left, `Expanded` counter; right, the Send button. Min height 48. |
| 4a | Counter | Shown only when `text.length >= 4500`: `chatCharacterCount(count, 5000)`, 13sp, `AppColors.ink` at alpha 0.75; at exactly 5000, w700 `AppColors.primaryDark`. `Semantics(liveRegion: true)`. Otherwise `SizedBox.shrink()`. |
| 4b | Send button | `FilledButton.icon(icon: Icon(Icons.send, size: 18), label: Text(sendButton))`, min size 48 high, `StadiumBorder`, padding h20. Enabled style: `AppColors.primary` background, white 16sp w600 label. Disabled style: `AppColors.sage` background, label and icon `AppColors.ink` at alpha 0.75. **Enabled only when** `_viewModel.canWrite && text.trim().isNotEmpty` (listen to the controller with `ValueListenableBuilder`). While `submit.running`: the icon becomes an 18x18 `CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryDark)` and the label `chatSending`. |

**Height cap.** Wrap the composer in
`ConstrainedBox(maxHeight: 0.6 × the body height)` so that, at large text
scales or in landscape, it never covers the whole body: the field scrolls
inside itself, and the lead-in keeps `maxLines: 3`.

### 4.6 Removed from the screen

`MessageBubble` (its only user is this screen: delete
`lib/ui/core/ui/message_bubble.dart`), the elevated cream keyword chips, the
first-writer `Material` card, the full-screen `CircularProgressIndicator`,
and the uses of `kMessageTextFieldDecoration` and `kSendButtonTextStyle`
(both become unused in `constants.dart`: delete them).
`kMessageContainerDecoration` stays.

## 5. Focus and keyboard

- **Don't auto-focus the field** when the lock is acquired (remove the
  `requestFocus` in `_onLockChanged`). The player reads the card first and
  taps the field when ready. On a 360x640 phone the auto-opened keyboard
  hides the whole card, which is the confusion we're fixing. See Q1.
- Tapping anywhere in the field opens the keyboard. Dragging the card
  dismisses it (`keyboardDismissBehavior.onDrag`).
- With the keyboard open, the composer sits on top of it (the Scaffold's
  default `resizeToAvoidBottomInset`), and the card scrolls in the space left.

## 6. States

| State | Turn card | Composer |
|---|---|---|
| 6.1 **First part** (`parts.isEmpty`) | Progress 1 of 4, `chatHeadlineFirst`, `chatLeadFirst`, no keywords, intro tips. | No lead-in. Field + Send. |
| 6.2 **Later part, keywords** | Progress n of 4, middle/last headline and lead, keywords section, tips. | Lead-in "Continua da qui: …5 words", field, Send. |
| 6.3 **Later part, no keywords** (not ready, failed, `[]`, legacy) | Same as 6.2 without the keywords section. **No placeholder, no "loading" text**: the screen doesn't listen for updates, so a placeholder would promise something that won't arrive. | Same as 6.2. |
| 6.4 **Reserving the turn** (`lock.running`) | Fully visible and readable. | 2dp linear progress at the top. Field disabled, hint `chatReservingTurn`. Send disabled. No full-screen spinner. |
| 6.5 **Sending** (`submit.running`) | Unchanged. | Field `readOnly: true` (keeps the ink text readable, unlike `enabled: false`). Send shows spinner + `chatSending`, disabled. AppBar close disabled, and system back blocked with `PopScope(canPop: !submit.running)`, so the unlock can't race the submit. |
| 6.6 **Sent** | — | Unchanged flow (notification offer if due, then `Navigator.pop`). **After the pop**, show a snackbar on the screen underneath: `chatCompletedSnackbar` if the position written was `epilogo`, otherwise `chatSentSnackbar`. Grab `ScaffoldMessenger.of(context)` before popping. |
| 6.7 **Lock error** | — | Unchanged: pop + error snackbar. |
| 6.8 **Submit error** | — | Unchanged: error snackbar. The text stays in the field, which becomes editable again. |
| 6.9 **Keyboard open, 360x640** | Scrolled behind, top part visible above the composer (or none of it at large text scales). | Lead-in + field (max 4 lines) + footer stay above the keyboard. See the budget below. |

**Height budget, 360x640 with the keyboard open (text scale 1.0):** status
bar 24 + AppBar 56 + keyboard ~260 = 340, so the body gets ~300dp. The
composer takes about 12 + lead-in 42 + 10 + field (4 lines) 112 + 8 +
footer 48 + 8 = 240. That leaves ~60dp of card visible. That's fine: the
5 words are in the composer, and the card can be scrolled.

## 7. Accessibility

| Item | Requirement |
|---|---|
| Reading order | Close, title, progress text, headline, lead, keywords heading, tags, caption, Remember heading, tips, lead-in (merged: "Continua da qui: …words"), field (label `chatInputLabel`), counter (if shown), Send. Widget order; no `sortKey`. |
| Headers | Headline, keywords heading and Remember heading have `header: true`, so screen-reader users can jump between them. |
| Tags | Not buttons: no `button` flag, no tap handler, no ripple. |
| Field | `Semantics(label: chatInputLabel(position))`. The hint is spoken while the field is empty. With `maxLength` set, Flutter reports the remaining characters to screen readers. |
| Send | Visible label (`sendButton` / `chatSending`). The disabled state is announced by the platform. |
| Status changes | Counter has `liveRegion: true`. Snackbars are announced by the platform. While locking, the progress bar is decorative (`ExcludeSemantics`); the hint `chatReservingTurn` explains it. |
| Tap targets | Close 48x48 (IconButton), Send at least 48 high, field at least 48 high. |
| Contrast | Ink on cream ~11.8:1. Ink on sage tags ~10:1. Ink at 0.75 alpha on cream ~6:1. `primaryDark` headings on cream ~6.6:1. White on `primary` (enabled Send) ~4.5:1 (AA, 16sp w600). Disabled Send: ink 0.75 on sage ~5:1. Future progress segments are decorative (the text says "Parte 2 di 4"). |
| Colour only | The current progress segment differs by colour, but the text states the position. Disabled vs enabled Send differ in both fill and label colour. |
| Text scaling | Tested at 2.0x: the card wraps freely (no `maxLines` except tags, 1 line + ellipsis, and the lead-in, 3 lines). The composer is capped at 60% of the body height, and the field scrolls inside. The AppBar title isn't clamped (it's short). |
| Dark mode | N/A, the app is light-only. |

## 8. Copy / l10n

`lib/l10n/app_it.arb` is the template: add `@key` descriptions (and
placeholders) there. Regenerate with `flutter gen-l10n`.

### Add

| Key | it | en |
|---|---|---|
| `chatPartProgress` | Parte {current} di {total} | Part {current} of {total} |
| `chatHeadlineFirst` | Inizia una storia nuova | Start a new story |
| `chatHeadlineMiddle` | Continua la storia | Continue the story |
| `chatHeadlineLast` | Scrivi il finale | Write the ending |
| `chatLeadFirst` | Sei il primo a scrivere: scegli tu personaggi, luogo e cosa succede. | You're the first to write: you choose the characters, the place and what happens. |
| `chatLeadMiddle` | Della storia vedi solo le ultime 5 parole: riparti da lì, con la tua fantasia. | You only get to see the last 5 words of the story: carry on from there, your way. |
| `chatLeadLast` | Della storia vedi solo le ultime 5 parole: portala a una conclusione. | You only get to see the last 5 words of the story: bring it to an end. |
| `chatKeywordsCaption` | Parole scelte in automatico leggendo tutte le parti scritte finora. | Picked automatically from all the parts written so far. |
| `chatTipsHeading` | Ricorda | Remember |
| `chatTipTurns` | Ogni storia ha 4 parti, scritte a turno da giocatori diversi: non puoi scriverne due di fila. | Every story has 4 parts, written in turns by different players: you can't write two in a row. |
| `chatTipHook` | Il prossimo giocatore vedrà solo le ultime 5 parole della tua parte: chiudi con un buon aggancio! | The next player only sees the last 5 words of your part, so end with a good hook! |
| `chatTipComplete` | Quando invii il finale, la storia è completa e tra poco appare nella scheda Complete. | Once you send the ending, the story is complete and soon appears in the Complete tab. |
| `chatTipLength` | Bastano poche frasi. Puoi scrivere fino a {max} caratteri. | A few sentences are enough. You can write up to {max} characters. |
| `chatTipLock` | Mentre scrivi, la storia è bloccata per gli altri. Se esci senza inviare, torna libera. | While you write, the story is locked for everyone else. If you leave without sending, it's free again. |
| `chatContinueFromLabel` | Continua da qui: | Carry on from here: |
| `chatLastWords` | …{words} | …{words} |
| `chatInputHint` | Scrivi qui la tua parte… | Write your part here… |
| `chatInputLabel` | La tua parte: {position} | Your part: {position} |
| `chatReservingTurn` | Sto riservando il tuo turno… | Reserving your turn… |
| `chatSending` | Invio… | Sending… |
| `chatCharacterCount` | {count}/{max} | {count}/{max} |
| `chatSentSnackbar` | Parte inviata! Ora tocca a qualcun altro. | Part sent! Now it's someone else's turn. |
| `chatCompletedSnackbar` | Storia completata! Tra poco la trovi nella scheda Complete. | Story complete! It'll show up in the Complete tab shortly. |

Placeholders:
- `current`, `total`, `count`, `max`: `int`. For `max` and `count`, use
  `"format": "decimalPattern"`, so they render as "5.000" in Italian and
  "5,000" in English.
- `words`, `position`: `String`. `chatLastWords` is a key so the ellipsis
  isn't a literal in code. Use the single character "…" (U+2026), not three
  dots. `{position}` in `chatInputLabel` is the position label as is (no
  `toLowerCase`).

The Italian copy avoids gendered forms except "Sei il primo a scrivere",
which is kept from the old `chatFirstWriterTitle` (see Q4).

### Change

| Key | Old (it / en) | New (it / en) |
|---|---|---|
| `storyKeywordsLabel` | Parole chiave / Keywords | Di cosa parla finora / What it's about so far |

It's now the visible heading of the keywords section, not just a
semantics label. Update its `@` description accordingly.

### Reuse, unchanged

`positionIntroduction`, `positionDevelopment1`, `positionDevelopment2`,
`positionEpilogue` (AppBar, `chatInputLabel`), `sendButton`, `genericError`,
`errorStoryAlreadyCompleted`, `errorStoryPositionTaken`,
`errorStoryLockedByOther`, `errorConsecutiveTurnNotAllowed`, the
notification offer strings.

### Remove (unused after this change)

`chatFirstWriterTitle`, `chatFirstWriterHint` (split into the tips),
`storySoFarLabel` (replaced by `chatContinueFromLabel`), `chatMessageHint`
(replaced by `chatInputHint` + `chatInputLabel`).

## 9. Edge cases

- **A very long "word".** `lastFiveWords` splits on whitespace, so a part
  with no spaces yields the whole part (up to 5000 chars). Today that whole
  text would show in the bubble. In the lead-in: if `lastFiveWords.length >
  120`, show only its **last 120 characters** (still after "…"). It's a
  subset of what's shown today, and it keeps the end, which is the part
  that matters. Cut on a grapheme boundary (`characters` package).
- **Keywords in the story's language, UI in the other:** expected. The
  keywords are content and aren't translated.
- **More than 4 keywords in the model:** `take(4)`.
- **A 24-character keyword at 2.0x on a narrow screen:** the tag ellipsizes
  at the card width. It never overflows.
- **Unknown `currentPosition`:** hide the progress row. Use the middle
  headline, lead and tips. The AppBar shows the raw value (as today).
- **Pasting more than 5000 characters:** `maxLengthEnforcement.enforced`
  truncates to 5000, and the counter shows 5000/5000 in bold. The server
  limit can no longer produce the generic error.
- **Whitespace-only text:** Send stays disabled (today it silently did
  nothing).
- **Closing with unsent text:** the text is lost and the story unlocked,
  as today. Optional confirmation in Q2.
- **The completed story is mature, or awaits review:** the "Complete" tab
  may not show it to a minor, or may show it only after the review.
  `chatCompletedSnackbar` says "tra poco" and doesn't promise that everyone
  can read it. See Q3.

## 10. Architecture notes

- **View-only.** All changes are in `chat_screen.dart` (plus private
  widgets in the same file or in `lib/ui/chat/widgets/`). `ChatViewModel`
  already exposes `story`, `canWrite`, `lock.running` and `submit.running`.
  The view decides the headline, lead and tips from
  `story.currentPosition`, and the snackbar from the position it submitted.
- **Max length constant.** Add `const int kMaxPartLength = 5000;` next to
  `kStoryPositions` in `lib/domain/models/story.dart`, documented as
  mirroring `part.text.size() <= 5000` in `firestore.rules`
  (like `Nickname.maxLength`). It's the only non-view change, and it's
  optional: a private constant in the view also works.
- The counter threshold (4500) and the lead-in cap (120) are view constants.
- No change to `test/architecture_test.dart`.

## 11. Acceptance criteria

1. **No chat look.** `ChatScreen` builds no `MessageBubble`, and
   `message_bubble.dart` is deleted. `storySoFarLabel`, `chatMessageHint`,
   `chatFirstWriterTitle` and `chatFirstWriterHint` are gone from both ARB
   files. `flutter gen-l10n` and `flutter analyze` are clean.
2. **Progress.** For each position, the card shows "Parte n di 4" / "Part
   n of 4" with n = 1..4, and 4 segments (n-1 done, 1 current, the rest
   future). Widget test for `introduzione` and `epilogo`.
3. **Headline, lead and tips by position.** introduzione: `chatHeadlineFirst`,
   `chatLeadFirst`, tips Turns+Hook+Length+Lock. sviluppo1/2:
   `chatHeadlineMiddle`, `chatLeadMiddle`, Hook+Length+Lock. epilogo:
   `chatHeadlineLast`, `chatLeadLast`, Complete+Length+Lock (and **no**
   Hook tip).
4. **Keywords.** With `keywords: [drago, faro, tempesta, segreto]` the
   heading "What it's about so far" (`storyKeywordsLabel`), the 4 tags and
   `chatKeywordsCaption` are shown, inside the card, above the Remember
   section. The tags have no tap action (`tester.tap` on one changes
   nothing, and their semantics have no `isButton`). With `keywords: []`
   and parts present, neither the heading, the tags nor the caption exist,
   and no placeholder text is shown. With no parts, no keywords section
   even if `keywords` is non-empty.
5. **Lead-in.** With parts, the composer shows `chatContinueFromLabel` and
   "…" + `lastFiveWords`, directly above the field (its bottom is above the
   field's top). With no parts, neither is shown. A last part of 300
   characters with no spaces shows exactly 120 characters after "…".
6. **No more story text.** No widget shows any text of any part other than
   `lastFiveWords` (test: a 2-part story whose first part has a unique word
   and whose last part has more than 5 words; neither the first part's word
   nor the 6th-from-last word is found).
7. **Send enablement.** Send is disabled while locking, with an empty or
   whitespace-only field, and while sending. It is enabled when the lock
   is held and the trimmed text is non-empty.
8. **Locking.** While `lock.running`: no full-screen spinner. A
   `LinearProgressIndicator` is in the composer, the field is disabled with
   hint `chatReservingTurn`, and the card is visible.
9. **No auto-focus.** After the lock is acquired the field doesn't have
   focus (`FocusNode.hasFocus == false`), unless Q1 decides otherwise.
10. **Sending.** While `submit.running`: Send shows a progress indicator
    and `chatSending`; the field is read-only and still shows the text; the
    close button is disabled, and system back doesn't pop.
11. **Sent.** After a successful submit of a non-final part, the screen
    pops and `chatSentSnackbar` is shown. For `epilogo`,
    `chatCompletedSnackbar`. With the notification offer, the snackbar
    appears after the dialog is answered and the screen pops.
12. **Errors.** Lock error and submit error behave as today (existing
    tests still pass, with finders updated from `TextButton` to the new
    Send button or `find.text('Send')`). After a submit error the text is
    still in the field and editable.
13. **Length.** The field accepts at most 5000 characters. The counter is
    absent below 4500 characters and shows "4.500/5.000" (it) / "4,500/5,000"
    (en) from 4500 on.
14. **Small phone + keyboard.** At 360x640, `viewInsets.bottom = 260`,
    text scale 1.0, with a later part and 4 keywords: no overflow errors;
    the lead-in text, the field and Send are all fully on screen.
15. **Large text.** At 320x640, text scale 2.0, with and without
    keyboard insets of 260: no overflow errors, and the composer is at
    most 60% of the body height.
16. **Semantics.** The headline, keywords heading and Remember heading are
    headers. The field's semantics label is `chatInputLabel(position)`.
    The lead-in is read as one node, "Continua da qui: …words".

## 12. Open product questions (defaults in bold)

- **Q1 Auto-focus.** **Don't open the keyboard automatically** (the player
  reads the card first) / keep today's auto-focus. Auto-focus saves one
  tap, but on small phones it hides the card on arrival.
- **Q2 Leave confirmation.** **None (as today)** / when closing with
  non-empty text, ask "Uscire senza inviare?" ("Quello che hai scritto
  andrà perso e la storia tornerà libera per gli altri." — buttons
  "Continua a scrivere" / "Esci"; EN "Leave without sending?", "What you've
  written will be lost and the story will be free for others again.",
  "Keep writing" / "Leave"). Children may lose a long paragraph with one
  tap on ✕. It needs 4 more keys (`chatLeaveTitle`, `chatLeaveBody`,
  `chatLeaveCancel`, `chatLeaveConfirm`) and a `PopScope`.
- **Q3 Completed snackbar for mature stories.** **Same text for all**
  ("tra poco la trovi nella scheda Complete") / a neutral "Storia
  completata!" without pointing at the tab, since a minor won't see a
  story the review flags as mature.
- **Q4 Gendered Italian.** "Sei il primo a scrivere" (kept from today) /
  a neutral "Tocca a te iniziare: scegli tu personaggi, luogo e cosa
  succede."
- **Q5 Tips for experienced players.** **Always shown** (3–4 short lines) /
  collapsed after the user has written N parts. Collapsing needs state
  outside the view, so it's out of scope for now.

## Implementation notes

Built in `lib/ui/chat/widgets/`: `chat_screen.dart` (screen, PopScope,
snack bars), `chat_turn_card.dart` (`ChatTurnCard`) and `chat_composer.dart`
(`ChatComposer`). `ChatViewModel` is unchanged; `kMaxPartLength` lives in
`lib/domain/models/story.dart`. Tests: `test/ui/chat/chat_screen_test.dart`.
Deviations from the spec above:

- **No tips / Remember section** (owner decision): §4.2 row 8, §4.4, the
  `chatTip*` keys and the Remember parts of §7 and §11 (3, 4, 16) are not
  built.
- **Leave confirmation (Q2):** the close button calls `Navigator.maybePop`;
  `PopScope.canPop` is false while sending or while the field has
  non-blank text, and then the `chatLeave*` dialog asks first (nothing
  happens while sending). Programmatic pops (lock error, after sending)
  aren't affected.
- **Field height with the keyboard open:** the spec's own budget (§6, a
  ~240dp composer in a ~300dp body) doesn't fit its 60% cap (§4.5). With
  the keyboard open the field starts at **1 line** (`minLines: 1`, still
  `maxLines: 4`) and its hint is kept to one line; without the keyboard
  it's 3 to 6 lines as specified. The composer's content is in a
  `SingleChildScrollView`, so when even that doesn't fit the cap (large
  text with the keyboard open, or once the text grows to 4 lines on a
  small phone) it scrolls inside the composer instead of overflowing.
- **Keyboard detection:** `Scaffold` removes the keyboard inset from its
  body's `MediaQuery`, so the screen reads `viewInsetsOf` above the
  Scaffold and passes `keyboardOpen` to the composer.
- **Card semantics:** `Card` merges its content into one node, which would
  spread the header flag over the whole card. The card's content and the
  keywords section are `Semantics(container: true, explicitChildNodes:
  true)`, so the headline, the keywords heading and each tag are separate
  nodes (tags as plain labels, no button flag).
- **Lead-in cap:** 120 grapheme clusters (`characters.takeLast`), and the
  counter counts graphemes too, like `maxLength`. `firestore.rules`'
  `size()` may count differently for emoji; untested.
- `chatCompletedSnackbar` follows Q3 ("Storia completata!" / "Story
  complete!") and `chatLeadFirst` follows Q4 in Italian.

**Owner change after device check (2026-10-15):** the last five words moved
out of the composer into a chat-style `MessageBubble` (restored), sender
label `chatContinueFromLabel`, under the turn card in the scrolling area.
With the keyboard open that area is anchored to the bottom
(`reverse: keyboardOpen`), so the bubble stays right above the composer.
The scrolling area is at least as tall as its viewport, with the card at the
top and the bubble aligned to the bottom (`MainAxisAlignment.spaceBetween`).
