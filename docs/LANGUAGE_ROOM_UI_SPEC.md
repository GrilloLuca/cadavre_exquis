# Language room in Account: UI/UX spec

Status: built. Q1 and Q2 are resolved (section 11). Branch: `feature/language-room-auto-detect`.
Replaces the room `PopupMenuButton` in the `HomeScreen` AppBar
(`lib/screens/home_screen.dart`, the `actions:` block).

Wireframe: `docs/language_room_wireframe.svg`.

## 1. Goal

The room the user plays in (one of the 5 language rooms, or a private room)
is chosen in one place: a new **Room** card on the Account (Profile) tab. The
story tabs keep only a small read-only indicator in the AppBar. Tapping it
opens the Profile tab.

On first launch the language room is picked automatically from the device
language. If no room matches, the app uses English. An explicit choice is
stored on the device only.

Out of scope: `PrivateRoomScreen` (reused as-is), the story lists, Firestore
queries, and the app UI locale (still only it/en).

## 2. Room selection rules (behaviour the UI reflects)

| Rule | Detail |
|---|---|
| Auto-detect | Use the **device** locales (`PlatformDispatcher.instance.locales`, in order). Pick the first whose `languageCode` matches a room in `kStoryLanguages`. **Do not** use `Localizations.localeOf(context)`: the app UI only supports it/en, so a Spanish device would resolve to the app's UI locale and never reach the `es` room. |
| No match | English (`en`). Note: `storyLanguageByCode` currently falls back to `kStoryLanguages.first` (`it`). The auto-detect path must not rely on that fallback. |
| Auto mode | While the user has not chosen a room, nothing is stored. Detection runs on each launch, so the room follows the device language until the user chooses. |
| Explicit choice | Tapping **any** language row, including the row that is already selected by auto-detect, stores that code on the device (`shared_preferences`, already a dependency) and ends auto mode. Not synced to Firestore. Kept across sign-out (it belongs to the device, not the account). |
| Startup | Read the stored code before the story tabs build their first query, so the list does not flash the auto-detected room and then switch. As built, `HomeScreen` resolves it in `initState` and shows a short progress indicator in place of the tabs until it is known, so there is only one story query at start-up. |
| Storage failure | If the write fails, keep the choice in memory for the session. No error UI. |
| Private room | Unchanged behaviour: kept in memory only and cleared on sign-out. While active it takes precedence over the language for listing and creating stories. |
| Language change while in a private room | Like the old menu, it **leaves** the private room and switches to that language room, which is also stored as the explicit choice. The leave is confirmed with the `privateRoomLeftSnackbar` snackbar and its Undo, which goes back into the private room (the new language stays stored). See Q1 (resolved). |
| Shared state | The Account card and the story tabs read the same state. A change in Account must show in the story tabs right away (they stay alive in the `IndexedStack`). How the state is shared (lifted controller or callbacks) is the developer's choice. |

## 3. Account screen layout

Order in the `Column`, inside the existing 480dp max-width layout:

```
avatar
16
email text (empty when there is no email)
[24, nickname card]        only when _email != null (unchanged)
24
Room card                  ALWAYS shown, also with no email/profile
32
Logout button
[16, delete account]       only when _email != null (unchanged)
```

The Room card does not depend on `_email`, `_loadFailed` or the nickname
loading state. It is never disabled by them.

## 4. The Room card

`CreamCard(padding: EdgeInsets.symmetric(vertical: 12.0))`. The header text
gets its own horizontal padding of 16. Rows are `ListTile`s with
`contentPadding: EdgeInsets.symmetric(horizontal: 16.0)`, so they line up
with the header.

### 4.1 Header (all states)

| Element | Spec |
|---|---|
| Title | `roomSectionTitle`. 18sp, w600, `AppColors.ink`. Wrap it in `Semantics(header: true)`. |
| Gap | 4 |
| Description | `roomSectionDescription`. 14sp, `AppColors.ink` at alpha 0.75 (the same style as the nickname public preview). No line limit. |
| Gap | 12 |
| Private-room notice | Only when a private room is active (section 4.4). |
| Subheading | `languageRoomHeading`. 14sp, w600, `AppColors.primaryDark`. `Semantics(header: true)`. Gap 4 below it. |

### 4.2 Language rows

One `ListTile` per entry of `kStoryLanguages`, in list order (it, en, es,
fr, de). The rows are always visible. There is no expand/collapse.

| Slot | Unselected | Selected |
|---|---|---|
| leading | Flag emoji, `fontSize: 24`, wrapped in `ExcludeSemantics` | same |
| title | `nativeName`, 16sp, w400, `AppColors.ink` | 16sp, **w600**, `AppColors.ink` |
| trailing | none | `Icons.check_circle`, 24dp, `AppColors.primaryDark` |
| background | transparent | `AppColors.sage`, `RoundedRectangleBorder(radius 10)`, inset 8dp horizontally from the card edge (the tile sits in `Padding(h: 8)` and its contentPadding becomes h8, so text still lines up at 16) |
| min height | 48dp (`minTileHeight: 48`) | same |
| tap | Select this language (section 2), `setState`. No snackbar, except in a private room: then the room is left and the "left" snackbar with Undo is shown (section 4.4) | Same. Tapping in auto mode stores the choice, and the caption disappears. |

The selected row is marked three ways: fill, weight and check icon. It does
not rely on colour alone.

### 4.3 Auto-detect caption

Shown under the 5 rows only in auto mode. 13sp, `AppColors.ink` at alpha
0.75, padding `fromLTRB(16, 4, 16, 0)`, with a leading
`Icons.smartphone` 16dp in `AppColors.primaryDark` and a gap of 6.

| Case | String |
|---|---|
| Device language matched a room | `languageRoomAutoDetected` |
| No match, English fallback | `languageRoomAutoFallback` |
| Explicit choice made | No caption. Remove the widget so it leaves no empty gap. |

Decision: **yes, show it.** Without it, a user on a Spanish phone who never
picked anything cannot tell why they are in the Spanish room, or that they
can change it. The caption costs one line and goes away for good once the
user chooses.

### 4.4 Private room active: precedence

When `privateRoom != null`:

1. **Notice** under the description, before the language subheading: a
   `Container` with `AppColors.sage` fill, radius 10, padding 12, margin h16,
   then a gap of 12 below. It is a `Row`: `Icons.lock` 20dp
   `AppColors.primaryDark`, gap 8, then `Expanded(Text(privateRoomActiveNotice(name)))`
   at 14sp in `AppColors.ink`.
2. **Language rows dimmed but still usable.** Titles use `AppColors.ink` at
   alpha 0.75 (still about 6:1 on cream). The selected row **drops the sage
   fill**, keeps w600, and its trailing icon becomes `Icons.check` 24dp in
   `AppColors.primaryDark`. This shows "the room you will return to" and not
   "the room you are in". Tapping a row leaves the private room and switches
   to that language room (section 2, Q1), with the `privateRoomLeftSnackbar`
   snackbar and Undo.
   Do **not** use `Opacity` or `enabled: false`. The rows still work and must
   stay above AA contrast.
3. The auto-detect caption, if any, still shows.

### 4.5 Private-room row

Placed after the language rows (and caption), following a `Divider(height: 24,
indent: 16, endIndent: 16)`. The rows stay in this order in every state, so
the layout does not jump around.

**Not in a private room**

| Slot | Spec |
|---|---|
| leading | `Icons.lock_outline`, 24dp, `AppColors.primary` |
| title | `privateRoomMenuItem` (reused: "Private room"), 16sp, `AppColors.ink` |
| subtitle | `privateRoomRowSubtitle`, 14sp, ink at alpha 0.75, max 2 lines |
| trailing | `Icons.chevron_right`, `AppColors.ink` at alpha 0.6 |
| tap | `Navigator.push<PrivateRoom>(PrivateRoomScreen())`. If it returns a room: set it as active and show the snackbar `privateRoomJoinedSnackbar(name)`. If it returns null (back): nothing happens. |

**In a private room**

| Slot | Spec |
|---|---|
| leading | `Icons.lock` (filled), 24dp, `AppColors.primaryDark` |
| title | `privateRoom.name`, 16sp, w600, `AppColors.ink`, max 2 lines, ellipsis |
| subtitle | `privateRoomMenuItem` ("Private room"), 14sp, ink at alpha 0.75 |
| trailing | `Icons.chevron_right` (same as above) |
| tap | Same as above. It opens `PrivateRoomScreen` to switch to another private room, and a returned room replaces the current one. |
| Leave button | On its own line under the tile, `Align(centerRight)`, padding `fromLTRB(16, 0, 8, 0)`: `TextButton.icon(icon: Icons.logout, label: leavePrivateRoomMenuItem)` (reused). `foregroundColor: AppColors.primaryDark`. It is not red, because leaving is harmless and can be undone. |
| Leave action | Clear the private room right away (no dialog) and show the snackbar `privateRoomLeftSnackbar(name)` with a `SnackBarAction(label: undoButton)` that restores the same `PrivateRoom` object. The undo does not need the password again. |

The Leave button sits on its own line, not in the tile's trailing slot.
This way the long "Esci dalla stanza privata" never squeezes the room name
on narrow screens.

## 5. AppBar indicator (story tabs only)

Replaces the `PopupMenuButton`. It is shown on tabs 0 and 1 and hidden on
tab 2 (Profile), as today.

| Item | Spec |
|---|---|
| AppBar title | Back to the plain tab title (`titles[_selectedIndex]`). **Remove** the `· privateRoom.name` suffix, because the indicator now shows the name. |
| Language room | The flag emoji, `fontSize: 20`, centered in the tap area. No `arrow_drop_down`, because this is no longer a menu. |
| Private room | `CircleAvatar(radius 14, cream, Icons.lock 18 primary)` (existing), gap 6, then the room name: white, 14sp, w600, 1 line, ellipsis, `maxWidth: 120dp`. The text uses `MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3)`. If the screen is narrower than 360dp, show the lock only. The full name is still in the tooltip and semantics. |
| Tap area | `InkWell` with `customBorder: StadiumBorder()`, padding h12, min 48x48 (`ConstrainedBox(minWidth: 48, minHeight: 48)`), 4dp right margin. |
| Tap | `setState(() => _selectedIndex = 2)`. It behaves exactly like tapping the Profile tab. No scroll or highlight is applied to the card. |
| Tooltip + semantics | Use the same string for both: `roomIndicatorLanguage(nativeName)` or `roomIndicatorPrivate(name)`. Set it up as `Semantics(button: true, label: …, excludeSemantics: true)` around `Tooltip(message: …, excludeFromSemantics: true)`, so the label is read once. |
| Contrast | White on `AppColors.primary` is about 4.5:1. That passes AA, and the w600 helps. |

## 6. States summary

| State | Account card | AppBar (tabs 0/1) |
|---|---|---|
| Auto, matched (e.g. es device) | Español selected (fill + check), caption `languageRoomAutoDetected`, private row "join" | 🇪🇸 |
| Auto, no match (e.g. ja device) | English selected, caption `languageRoomAutoFallback` | 🇬🇧 |
| Explicitly chosen | Chosen row selected, no caption | Flag of the chosen room |
| In a private room | Notice, dimmed rows (chosen one with plain check; tapping any row leaves the private room), active private row + Leave | Lock + name (ellipsis) |
| No email / no profile | Room card shown exactly as in the other states. The nickname card and delete button stay hidden. | Unchanged |
| Narrow (320dp) + text scale 2.0 | Rows grow vertically, and all text wraps (no `maxLines` except the room name, which has 2). The notice wraps. The Leave button stays on its own line. Nothing is clipped, because the screen already scrolls. | Lock only below 360dp. Otherwise the name is clamped to 1.3x and ellipsized. |

No empty or error state is needed. The rooms list is a constant, the
stored code is read before the story tabs are built (a brief progress
indicator in `HomeScreen`), and a failed write is silent (section 2).

## 7. Accessibility

| Item | Requirement |
|---|---|
| Language rows | Each row: `Semantics(inMutuallyExclusiveGroup: true, checked: isSelected, button: true)`. The flag is excluded, so the row reads "Español, selected" or "English, not selected". |
| Headers | Card title and "Language room" subheading have `header: true`, so users can jump between headings. |
| Notice | Plain text, read in order. The lock icon is decorative (`excludeFromSemantics`). |
| Private row | `ListTile` merges its children. Not in a room it reads "Private room, Play only with friends who know its name and password". In a room it reads "<name>, Private room". |
| Leave button | Text button with a visible label. No extra semantics needed. |
| Snackbars | Announced by the platform. The Undo action is reachable by the screen reader. |
| Focus / reading order | Title, description, notice (if any), subheading, the 5 rows, caption, private row, Leave. Then Logout. Keep it as widget order, with no `sortKey`. |
| Tap targets | Language rows at least 48dp tall, private row at least 56dp, Leave button at least 48dp (the `TextButton` default), AppBar indicator at least 48x48. |
| Contrast | Ink on cream about 11.8:1. Ink on sage about 10:1. Ink at 0.75 alpha on cream about 6:1. `primaryDark` icons on cream/sage are above 5:1. |
| Text scaling | Tested at 2.0x. Only the AppBar name is clamped (1.3x), because the AppBar has a fixed height. Its full text stays available in the tooltip and semantics label. |
| Dark mode | N/A. The app is light-only. |

## 8. Copy / l10n

`lib/l10n/app_it.arb` is the template. Add `@key` descriptions there.

### Add

| Key | it | en |
|---|---|---|
| `roomSectionTitle` | Stanza | Room |
| `roomSectionDescription` | Vedi e scrivi solo le storie della stanza in cui ti trovi. | You only see and write stories in the room you're in. |
| `languageRoomHeading` | Stanza della lingua | Language room |
| `languageRoomAutoDetected` | Scelta in base alla lingua del dispositivo. | Picked from your device language. |
| `languageRoomAutoFallback` | Non c'è ancora una stanza nella lingua del dispositivo, quindi sei in quella inglese. | There's no room in your device language yet, so you're in the English one. |
| `privateRoomRowSubtitle` | Gioca solo con gli amici che ne conoscono nome e password. | Play only with friends who know its name and password. |
| `privateRoomActiveNotice` | Sei nella stanza privata “{name}”. La stanza della lingua è in pausa finché non esci. | You're in the private room “{name}”. The language room is paused until you leave. |
| `privateRoomJoinedSnackbar` | Ora sei in “{name}”. | You're now in “{name}”. |
| `privateRoomLeftSnackbar` | Hai lasciato “{name}”. | You left “{name}”. |
| `undoButton` | Annulla | Undo |
| `roomIndicatorLanguage` | Stanza: {language}. Cambiala nel Profilo. | Room: {language}. Change it in Profile. |
| `roomIndicatorPrivate` | Stanza privata: {name}. Cambiala nel Profilo. | Private room: {name}. Change it in Profile. |

Placeholders: `name` and `language` are both `String`. Declare them in the
`@key` entries of `app_it.arb`. The Italian strings avoid gendered
participles ("Ora sei in", "Hai lasciato") on purpose. `{language}` is the
room's `nativeName` (e.g. "Español"), which matches what the list shows.

### Reuse, unchanged

`privateRoomMenuItem` (private-row title and subtitle),
`leavePrivateRoomMenuItem` (Leave button label). Their key names still say
"MenuItem". Do not rename them in this change.

### Remove

`languageRoomTooltip`. It only made sense for the menu ("Choose the language
room"). The read-only indicator needs the current room in its label, so
`roomIndicatorLanguage` / `roomIndicatorPrivate` replace it. Remove it from
both ARB files.

Regenerate with `flutter gen-l10n`. Do not edit the generated files.

## 9. Edge cases

- **The device language changes while in auto mode:** the next launch picks
  the new room. If the change happens while the app is running, there is no
  live switch. The new language applies on the next start.
- **A stored code that is no longer in `kStoryLanguages`** (a room removed
  later): treat it as no stored code and run auto-detect.
- **Region-only differences** (`es_MX`, `de_AT`, `en_US`): match on
  `languageCode` only.
- **Tapping the indicator while a story list is loading:** it just switches
  tab. The lists keep their state.
- **Pressing Leave twice quickly:** the second press does nothing, because
  the button is no longer shown once the room is cleared.
- **Undo after joining another room:** the Undo restores the room that was
  left and replaces whatever room is current. This is fine, because the
  snackbar only lasts about 4 seconds.
- **Sign-out:** the private room is cleared. The stored language stays.

## 10. Acceptance criteria

1. `HomeScreen` has no `PopupMenuButton`. On tabs 0/1 the AppBar shows a
   read-only indicator: the flag for a language room, or lock + ellipsized
   name for a private room (lock only below 360dp). Tapping it selects tab 2.
   It is hidden on tab 2.
2. The AppBar title no longer has the `· <room name>` suffix.
3. The indicator's tooltip and semantics label are `roomIndicatorLanguage` /
   `roomIndicatorPrivate`, read once, with `button: true`, and the target is
   at least 48x48.
4. On Account, the Room card sits between the nickname card and Logout. It is
   rendered when `email == null` too (widget test with no email: the card is
   found and the nickname field is not).
5. The card lists the 5 rooms (flag + native name) in `kStoryLanguages`
   order. Exactly one is selected (sage fill, w600, `check_circle`), and its
   semantics are `checked: true` + `inMutuallyExclusiveGroup`.
6. Fresh install, device locales `[es_ES]`: Español is selected, the caption
   is `languageRoomAutoDetected`, the stories use `es`, and nothing is
   stored. Device `[ja_JP]`: English is selected and the caption is
   `languageRoomAutoFallback`. Device `[ja_JP, fr_FR]`: Français is selected.
7. Tapping any language row stores it on the device, removes the caption, and
   updates the story tabs right away. After a restart the stored room is used
   even if the device language differs, and the auto-detected room does not
   flash first.
8. Private row (not in a room) → `PrivateRoomScreen`. If a room is returned:
   the snackbar `privateRoomJoinedSnackbar`, the notice appears, the language
   rows dim (selected row: no fill, `Icons.check`), and the private row shows
   the room name + Leave. Back without a room: no change.
9. While in a private room, tapping a language leaves the room, switches to
   and stores that language, and shows `privateRoomLeftSnackbar` with Undo.
   The notice and the Leave button go away; Undo brings them back.
10. Leave clears the room with no dialog and shows `privateRoomLeftSnackbar`
    with Undo. Undo restores the same room.
11. At 320dp width and text scale 2.0, the Account screen shows no overflow
    errors and all card text is readable (wraps). This is covered by a widget
    test with `tester.view` set to 320x640 and `textScaler` 2.0.
12. ARB files: the 12 new keys exist in it and en. `languageRoomTooltip` is
    removed. `flutter gen-l10n` and `flutter analyze` are clean.

## 11. Product questions (resolved)

- **Q1 Language tap while in a private room. Resolved: it leaves the
  private room**, like the old menu did, and switches to that language room.
  The designer's proposed default (only changing the room you return to)
  was not adopted. To avoid a silent side effect, the leave is confirmed
  with the `privateRoomLeftSnackbar` snackbar and Undo.
- **Q2 Persisting the private room. Resolved: not persisted.** It stays in
  memory only, as before, so users rejoin after a restart.
