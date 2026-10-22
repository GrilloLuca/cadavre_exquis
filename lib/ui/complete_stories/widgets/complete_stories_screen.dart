import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/story/story_repository.dart';
import 'package:cadavre_exquisite/domain/models/app_config.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/domain/use_cases/age_gate.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/ui/complete_stories/view_models/complete_stories_view_model.dart';
import 'package:cadavre_exquisite/ui/complete_stories/widgets/age_check_screen.dart';
import 'package:cadavre_exquisite/ui/core/themes/app_colors.dart';
import 'package:cadavre_exquisite/ui/core/themes/constants.dart';
import 'package:cadavre_exquisite/ui/core/ui/background.dart';
import 'package:cadavre_exquisite/ui/core/ui/cream_card.dart';
import 'package:cadavre_exquisite/ui/core/view_models/mature_story_access.dart';
import 'package:cadavre_exquisite/ui/story_read/widgets/story_read_screen.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// Index of the "Your stories" tab; everyone else's come first.
const _yourStoriesTab = 1;

/// Longest search the field accepts (no visible counter).
const _maxQueryLength = 50;

/// [text] as shown inside the no-match messages: trimmed, with inner runs
/// of whitespace collapsed to one space.
String _displayQuery(String text) =>
    text.trim().replaceAll(RegExp(r'\s+'), ' ');

/// The completed stories of the room, newest first, in two tabs: everyone
/// else's, and those the user wrote a part of. Stories the AI review
/// flagged as mature are listed with the others but locked behind the age
/// check ([AgeGate]); known minors see them as disabled "unavailable" tiles
/// (docs/PART_MODERATION_UI_SPEC.md §3), or not at all when
/// [AppConfig.matureVisibleToMinors] is off. Stories still awaiting their
/// review aren't listed. A search field
/// above the tabs filters both by AI title and keywords (see
/// docs/STORY_SEARCH_UI_SPEC.md). Creates its [CompleteStoriesViewModel]
/// once, in `initState` (see `ChatScreen`).
class CompleteStoriesScreen extends StatefulWidget {
  /// Language code of the room the user has joined: only stories in this
  /// language are listed.
  final String language;

  /// Id of the private room the user has joined, if any. When set, this
  /// takes precedence over [language]: only stories in this room are listed.
  final String? roomId;

  const CompleteStoriesScreen({
    super.key,
    required this.language,
    this.roomId,
  });

  @override
  State<CompleteStoriesScreen> createState() => _CompleteStoriesScreenState();
}

class _CompleteStoriesScreenState extends State<CompleteStoriesScreen>
    with SingleTickerProviderStateMixin {
  late final CompleteStoriesViewModel _viewModel;
  late final TabController _tabs;

  // One controller per list: two lists on the PrimaryScrollController
  // break its scrollbar on iOS and desktop, where it's interactive.
  final _yourStoriesScroll = ScrollController();
  final _otherStoriesScroll = ScrollController();

  /// The search field's text and focus. The ViewModel holds the query the
  /// lists are filtered by; the View keeps the two in step.
  late final TextEditingController _search;
  late final FocusNode _searchFocus;

  /// Whether the current room's stories had arrived at the last change;
  /// see [_onViewModelChanged].
  bool _wasLoaded = false;

  @override
  void initState() {
    super.initState();
    _viewModel = CompleteStoriesViewModel(
      storyRepository: context.read<StoryRepository>(),
      authRepository: context.read<AuthRepository>(),
      ageGate: context.read<AgeGate>(),
      language: widget.language,
      roomId: widget.roomId,
      matureVisibleToMinors: context.read<AppConfig>().matureVisibleToMinors,
    );
    _tabs = TabController(length: 2, vsync: this);
    _search = TextEditingController();
    _searchFocus = FocusNode();
    _viewModel.addListener(_onViewModelChanged);
    _viewModel.unlock.addListener(_onUnlockChanged);
    _viewModel.submitBirthYear.addListener(_onSubmitBirthYearChanged);
  }

  @override
  void didUpdateWidget(CompleteStoriesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The user switched room or language: the ViewModel drops the query
    // (an old one would quietly hide the new room's stories), so the field
    // is emptied too.
    if (widget.language != oldWidget.language ||
        widget.roomId != oldWidget.roomId) {
      _search.clear();
    }
    _viewModel.setRoom(language: widget.language, roomId: widget.roomId);
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.unlock.removeListener(_onUnlockChanged);
    _viewModel.submitBirthYear.removeListener(_onSubmitBirthYearChanged);
    _viewModel.dispose();
    _tabs.dispose();
    _yourStoriesScroll.dispose();
    _otherStoriesScroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// When a room's stories arrive, opens on the user's tab if only that
  /// one has stories. The tabs aren't shown before, so nothing jumps.
  ///
  /// If the room has no story left while a search is typed (say its only
  /// stories were deleted), the field goes away, and so does the search, so
  /// no invisible filter is left behind. With mature stories visible to
  /// minors, a minor verdict never empties the list (they stay, as
  /// unavailable tiles); with them hidden, it may, and the search goes too.
  void _onViewModelChanged() {
    final loaded = _viewModel.isLoaded;
    if (loaded && !_wasLoaded) {
      final (:mine, :others) = _viewModel.totalCounts;
      _tabs.index = others == 0 && mine > 0 ? _yourStoriesTab : 0;
    }
    _wasLoaded = loaded;
    if (loaded && _search.text.isNotEmpty) {
      final (:mine, :others) = _viewModel.totalCounts;
      if (mine + others == 0) {
        _searchFocus.unfocus();
        _search.clear();
        _viewModel.setQuery('');
      }
    }
  }

  void _onSearchChanged(String text) {
    _viewModel.setQuery(text);
    _scrollListsToTop();
  }

  /// Empties the search, from the clear button or the no-match card.
  /// Leaves the focus as it is.
  void _clearSearch() {
    _search.clear();
    _viewModel.setQuery('');
    _scrollListsToTop();
  }

  /// Results always start at the top after the user changes the search.
  void _scrollListsToTop() {
    for (final controller in [_otherStoriesScroll, _yourStoriesScroll]) {
      if (controller.hasClients) controller.jumpTo(0);
    }
  }

  void _openStory(Story story) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryReadScreen(story: story),
      ),
    );
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Acts on the outcome of an unlock step: opens the story for adults,
  /// tells minors it's unavailable, or shows the birth-year screen.
  Future<void> _handle(Command<UnlockResult> command) async {
    if (command.running) return;
    final l10n = AppLocalizations.of(context)!;
    if (command.error != null) {
      command.clearResult();
      _showSnackBar(l10n.genericError);
      return;
    }
    final result = command.value;
    if (!command.completed || result == null) return;
    command.clearResult();
    switch (result.outcome) {
      case UnlockOutcome.open:
        _openStory(result.story);
      case UnlockOutcome.minor:
        _showSnackBar(l10n.matureStoryUnavailable);
      case UnlockOutcome.askBirthYear:
        final birthYear = await Navigator.push<int>(
          context,
          MaterialPageRoute(builder: (_) => const AgeCheckScreen()),
        );
        if (!mounted) return;
        if (birthYear == null) {
          _viewModel.cancelBirthYear();
        } else {
          _viewModel.submitBirthYear.execute(birthYear);
        }
      case UnlockOutcome.ignored:
        break;
    }
  }

  void _onUnlockChanged() => _handle(_viewModel.unlock);

  void _onSubmitBirthYearChanged() => _handle(_viewModel.submitBirthYear);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Background(
        opacity: 0.2,
        child: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            if (!_viewModel.isLoaded) {
              return const Center(child: CircularProgressIndicator());
            }

            // "No stories" is decided without the search; a search only
            // ever leads to "no matches".
            final totals = _viewModel.totalCounts;
            if (totals.mine + totals.others == 0) {
              return _buildEmpty(l10n.noCompleteStories);
            }

            // Both tabs keep the repository's order (newest completed
            // first).
            final (:mine, :others) = _viewModel.sections;
            final searching = _viewModel.isSearching;
            String tabLabel(String label, int count) =>
                searching ? l10n.storiesTabCount(label, count) : label;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 4.0),
                  child: _buildSearchField(l10n),
                ),
                // Inside the field's tap region, so switching tab doesn't
                // close the keyboard.
                TextFieldTapRegion(
                  child: TabBar(
                    controller: _tabs,
                    labelColor: AppColors.primaryDark,
                    unselectedLabelColor: AppColors.ink,
                    indicatorColor: AppColors.primaryDark,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                    tabs: [
                      _buildTab(tabLabel(l10n.otherStoriesTab, others.length)),
                      _buildTab(tabLabel(l10n.yourStoriesHeading, mine.length)),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _buildTabBody(
                        l10n,
                        stories: others,
                        total: totals.others,
                        noStories: l10n.noOtherCompleteStories,
                        otherTabMatches: mine.length,
                        otherTabIndex: _yourStoriesTab,
                        otherTabLabel: l10n.yourStoriesHeading,
                        controller: _otherStoriesScroll,
                        storageKey: const PageStorageKey('otherStories'),
                      ),
                      _buildTabBody(
                        l10n,
                        stories: mine,
                        total: totals.mine,
                        noStories: l10n.noYourCompleteStories,
                        otherTabMatches: others.length,
                        otherTabIndex: 0,
                        otherTabLabel: l10n.otherStoriesTab,
                        controller: _yourStoriesScroll,
                        storageKey: const PageStorageKey('yourStories'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchField(AppLocalizations l10n) {
    // The label names the field also once text hides the hint. Rebuilt
    // with the text alone (for the clear button), not the whole screen.
    return Semantics(
      label: l10n.searchStoriesLabel,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _search,
        builder: (context, value, _) => TextField(
          key: const ValueKey('storySearchField'),
          controller: _search,
          focusNode: _searchFocus,
          decoration: kTextFieldDecoration.copyWith(
            filled: true,
            fillColor: AppColors.cream,
            hintText: l10n.searchStoriesHint,
            hintMaxLines: 1,
            hintStyle: TextStyle(color: AppColors.ink.withValues(alpha: 0.7)),
            prefixIcon: const Icon(
              Icons.search,
              color: AppColors.primaryDark,
              size: 24.0,
            ),
            // Any text, spaces included, so stray spaces can be cleared.
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    key: const ValueKey('storySearchClear'),
                    icon: const Icon(Icons.close),
                    color: AppColors.ink,
                    tooltip: l10n.clearSearch,
                    onPressed: _clearSearch,
                  ),
          ),
          style: const TextStyle(color: AppColors.ink, fontSize: 16.0),
          cursorColor: AppColors.primaryDark,
          textInputAction: TextInputAction.search,
          keyboardType: TextInputType.text,
          autocorrect: false,
          enableSuggestions: true,
          textCapitalization: TextCapitalization.none,
          inputFormatters: [
            LengthLimitingTextInputFormatter(_maxQueryLength),
          ],
          onChanged: _onSearchChanged,
          // Results are already live: the keyboard action only closes it.
          onSubmitted: (_) => _searchFocus.unfocus(),
          onTapOutside: (_) => _searchFocus.unfocus(),
        ),
      ),
    );
  }

  Widget _buildTab(String label) {
    return Tab(
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  /// One tab's list, or the card explaining why it's empty: no stories at
  /// all in this tab, no match here but some in [otherTabIndex], or no
  /// match anywhere.
  Widget _buildTabBody(
    AppLocalizations l10n, {
    required List<Story> stories,
    required int total,
    required String noStories,
    required int otherTabMatches,
    required int otherTabIndex,
    required String otherTabLabel,
    required ScrollController controller,
    required Key storageKey,
  }) {
    if (total == 0) return _buildEmpty(noStories);
    if (stories.isNotEmpty) {
      return _buildStoryList(stories, controller, storageKey);
    }
    // Searching, and nothing here matches.
    if (otherTabMatches > 0) {
      return _buildEmptyCard([
        _buildNoMatchMessage(l10n.noMatchingStoriesHere),
        const SizedBox(height: 8.0),
        _buildCardButton(
          l10n.showMatchesInTab(otherTabMatches, otherTabLabel),
          () => _tabs.animateTo(otherTabIndex),
        ),
      ]);
    }
    return _buildEmptyCard([
      _buildNoMatchMessage(l10n.noMatchingStories),
      const SizedBox(height: 8.0),
      Text(
        l10n.noMatchingStoriesHint,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.ink, fontSize: 14.0),
      ),
      const SizedBox(height: 8.0),
      _buildCardButton(l10n.clearSearch, _clearSearch),
    ]);
  }

  /// A no-match message quoting the search, announced when it appears.
  /// Follows the field's text, which may change without the lists
  /// changing (a trailing word too short to filter).
  Widget _buildNoMatchMessage(String Function(String query) message) {
    return Semantics(
      liveRegion: true,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _search,
        builder: (context, value, _) => Text(
          message(_displayQuery(value.text)),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.ink),
        ),
      ),
    );
  }

  Widget _buildCardButton(String label, VoidCallback onPressed) {
    // Inside the field's tap region, so the keyboard stays as it is.
    return TextFieldTapRegion(
      child: TextButton(
        style: TextButton.styleFrom(foregroundColor: AppColors.primaryDark),
        onPressed: onPressed,
        child: Text(
          label,
          maxLines: 2,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildEmpty(String text) {
    return _buildEmptyCard([
      Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.ink),
      ),
    ]);
  }

  Widget _buildEmptyCard(List<Widget> children) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: CreamCard(
          padding: const EdgeInsets.symmetric(
            horizontal: 20.0,
            vertical: 16.0,
          ),
          child: children.length == 1
              ? children.single
              : Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }

  /// A scrollable list of story cards, with a scrollbar. The [storageKey]
  /// keeps each tab's scroll offset when the user switches tabs.
  Widget _buildStoryList(
    List<Story> stories,
    ScrollController controller,
    Key storageKey,
  ) {
    return Scrollbar(
      controller: controller,
      child: ListView.builder(
        key: storageKey,
        controller: controller,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(12.0),
        itemCount: stories.length,
        itemBuilder: (context, index) =>
            _buildStoryCard(context, stories[index]),
      ),
    );
  }

  Widget _buildStoryCard(BuildContext context, Story story) {
    final l10n = AppLocalizations.of(context)!;
    final mature = _viewModel.matureStateOf(story);

    final Widget tile;
    switch (mature) {
      case MatureTileState.locked:
        // The AI title is generated child-safe, so it is shown; the part
        // text never is, as it can contain what the review flagged. A story
        // the model refused to read has no title and falls back to the
        // label.
        final title = story.title;
        tile = Semantics(
          button: true,
          onTapHint: l10n.matureStoryUnlockHint,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            iconColor: AppColors.primary,
            textColor: AppColors.ink,
            leading: Icon(
              Icons.lock,
              size: 24.0,
              color: AppColors.primaryDark,
              semanticLabel: l10n.matureStoryLockedLabel,
            ),
            title: Text(
              title ?? l10n.matureStoryLockedTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: _buildSubtitle(
              l10n,
              story,
              title == null
                  ? l10n.authorsCount(story.parts.length)
                  : '${l10n.matureStoryLockedTitle} · '
                      '${l10n.authorsCount(story.parts.length)}',
            ),
            trailing: _viewModel.checkingStoryId == story.id
                ? const SizedBox(
                    width: 18.0,
                    height: 18.0,
                    child: CircularProgressIndicator(strokeWidth: 2.0),
                  )
                : null,
            onTap: () {
              // Unfocused first, so coming back doesn't reopen the keyboard.
              _searchFocus.unfocus();
              _viewModel.unlock.execute(story);
            },
          ),
        );
      case MatureTileState.unavailable:
        // A known minor's tile: disabled, the reason in the subtitle, and
        // no tap action, so the age check never runs. Same title rule as a
        // locked tile (the AI title is child-safe), never the part text.
        // The padlock and the keywords take the disabled tint.
        tile = ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 8.0,
          ),
          iconColor: AppColors.primary,
          textColor: AppColors.ink,
          enabled: false,
          leading: Icon(
            Icons.lock,
            size: 24.0,
            semanticLabel: l10n.matureStoryLockedLabel,
          ),
          title: Text(
            story.title ?? l10n.matureStoryLockedTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: _buildSubtitle(
            l10n,
            story,
            '${l10n.matureStoryUnavailableLabel} · '
            '${l10n.authorsCount(story.parts.length)}',
            disabled: true,
          ),
        );
      case MatureTileState.hidden:
        // Never listed (the ViewModel leaves hidden stories out).
        return const SizedBox.shrink();
      case MatureTileState.none:
      case MatureTileState.unlocked:
        final preview = story.parts.isNotEmpty ? story.parts.first.text : '';
        tile = ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 8.0,
          ),
          iconColor: AppColors.primary,
          textColor: AppColors.ink,
          leading: const Icon(Icons.menu_book),
          title: Text(
            story.title ?? preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: _buildSubtitle(
              l10n, story, l10n.authorsCount(story.parts.length)),
          trailing: mature == MatureTileState.unlocked
              ? Icon(
                  Icons.lock_open,
                  size: 20.0,
                  semanticLabel: l10n.matureStoryAdultContent,
                )
              : null,
          onTap: () {
            _searchFocus.unfocus();
            _openStory(story);
          },
        );
    }

    // Keyed by story, so a tile that changes state in place keeps
    // screen-reader focus.
    return Padding(
      key: ValueKey(story.id),
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: CreamCard(child: tile),
    );
  }

  /// The tile's [text] line and, when the story has keywords, a line with
  /// them; while searching, the matching ones are bold. Keywords are
  /// generated child-safe, so locked and unavailable tiles show them too.
  /// On a [disabled] tile they take the disabled tint, like the title, and
  /// matches stay bold.
  Widget _buildSubtitle(
    AppLocalizations l10n,
    Story story,
    String text, {
    bool disabled = false,
  }) {
    final keywords = story.keywords;
    if (keywords.isEmpty) return Text(text);
    final searching = _viewModel.isSearching;
    final disabledColor = Theme.of(context).disabledColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        const SizedBox(height: 4.0),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1.0),
              child: ExcludeSemantics(
                child: Icon(
                  Icons.tag,
                  size: 14.0,
                  color: disabled ? disabledColor : AppColors.primaryDark,
                ),
              ),
            ),
            const SizedBox(width: 4.0),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    for (var i = 0; i < keywords.length; i++) ...[
                      if (i > 0) const TextSpan(text: ' · '),
                      TextSpan(
                        text: keywords[i],
                        style: searching && _viewModel.highlights(keywords[i])
                            ? TextStyle(
                                fontWeight: FontWeight.w700,
                                color: disabled
                                    ? disabledColor
                                    : AppColors.primaryDark,
                              )
                            : null,
                      ),
                    ],
                  ],
                ),
                semanticsLabel:
                    l10n.storyKeywordsSemantics(keywords.join(', ')),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.0,
                  fontWeight: FontWeight.w400,
                  color: disabled ? disabledColor : AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
