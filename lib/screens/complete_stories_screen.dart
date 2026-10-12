import 'package:cadavre_exquisite/app_colors.dart';
import 'package:cadavre_exquisite/background.dart';
import 'package:cadavre_exquisite/cream_card.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cadavre_exquisite/l10n/app_localizations.dart';
import 'package:cadavre_exquisite/models/story.dart';
import 'package:cadavre_exquisite/services/age_check_service.dart';
import 'package:cadavre_exquisite/services/age_gate.dart';
import 'package:cadavre_exquisite/services/story_service.dart';
import 'package:cadavre_exquisite/services/user_profile_service.dart';
import 'package:cadavre_exquisite/screens/age_check_screen.dart';
import 'package:cadavre_exquisite/screens/story_read_screen.dart';

/// Non-story rows in the complete stories list.
enum _ListMarker { yourStoriesHeading, divider }

/// The completed stories of the room, newest first. Stories the AI review
/// flagged as mature are listed with the others but locked behind the age
/// check ([AgeGate]); known minors don't see them at all.
class CompleteStoriesScreen extends StatefulWidget {
  /// Language code of the room the user has joined: only stories in this
  /// language are listed.
  final String language;

  /// Id of the private room the user has joined, if any. When set, this
  /// takes precedence over [language]: only stories in this room are listed.
  final String? roomId;

  /// Source of the stories. Defaults to a [StoryService] on the default
  /// Firestore instance; injectable for tests.
  final StoryService? storyService;

  /// Decides access to mature stories. Defaults to [AgeGate]; injectable
  /// for tests.
  final AgeGate? ageGate;

  /// Stores the birth year asked when [ageGate] has no answer. Defaults to
  /// [AgeCheckService]; inject the same storage as [ageGate] in tests.
  final AgeCheckService? ageCheckService;

  /// Passed to [StoryReadScreen] for the authors' nicknames; injectable for
  /// tests.
  final UserProfileService? profileService;

  /// Email of the signed-in user. Defaults to the current [FirebaseAuth]
  /// user's; when provided, [FirebaseAuth] is never accessed.
  final String? email;

  const CompleteStoriesScreen({
    super.key,
    required this.language,
    this.roomId,
    this.storyService,
    this.ageGate,
    this.ageCheckService,
    this.profileService,
    this.email,
  });

  /// Forgets who was found adult or minor this session, so mature stories
  /// are locked again. Call on sign-out.
  static void clearSessionState() {
    _CompleteStoriesScreenState._sessionMinors.clear();
    _CompleteStoriesScreenState._sessionAdults.clear();
  }

  @override
  State<CompleteStoriesScreen> createState() => _CompleteStoriesScreenState();
}

class _CompleteStoriesScreenState extends State<CompleteStoriesScreen> {
  /// Users found to be minors this app session (profile keys): their
  /// mature stories stay hidden even when the list is rebuilt from scratch.
  static final Set<String> _sessionMinors = {};

  /// Users found to be adults this app session (profile keys): their
  /// mature stories are unlocked until the app restarts or they sign out.
  static final Set<String> _sessionAdults = {};

  late final AgeCheckService _storage =
      widget.ageCheckService ?? AgeCheckService();
  late final AgeGate _gate = widget.ageGate ?? AgeGate(storage: _storage);
  late Stream<List<Story>> _stories;

  String? _email;
  int? _birthYear;

  /// Whether the quiet birth-year read has finished (or failed, or there is
  /// no user). Until then mature stories are hidden, so a stored minor never
  /// sees a locked tile flash in before the read lands.
  bool _birthYearLoaded = false;

  /// Id of the mature story whose age check is running, null when idle.
  /// Only one check runs at a time.
  String? _checkingStoryId;

  @override
  void initState() {
    super.initState();
    _email = widget.email ?? FirebaseAuth.instance.currentUser?.email;
    _stories = _subscribe();
    _loadBirthYear();
  }

  @override
  void didUpdateWidget(CompleteStoriesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The user switched room or language.
    if (oldWidget.language != widget.language ||
        oldWidget.roomId != widget.roomId ||
        oldWidget.storyService != widget.storyService) {
      _stories = _subscribe();
    }
  }

  /// Kept in the state so rebuilds (spinner, unlock) don't resubscribe.
  Stream<List<Story>> _subscribe() =>
      (widget.storyService ?? StoryService()).completeStoriesStream(
        language: widget.language,
        roomId: widget.roomId,
      );

  /// Quietly reads the stored birth year, to hide mature stories from known
  /// minors. Never asks the platform: that may show a system sheet, so it
  /// only happens on tap.
  Future<void> _loadBirthYear() async {
    final email = _email;
    if (email == null) {
      _birthYearLoaded = true;
      return;
    }
    int? birthYear;
    try {
      birthYear = await _gate.storedBirthYear(email);
    } catch (_) {
      // Unknown age: mature stories stay locked and the check runs on tap.
    }
    if (!mounted) return;
    setState(() {
      _birthYear = birthYear;
      _birthYearLoaded = true;
    });
  }

  String? get _profileKey {
    final email = _email;
    return email == null ? null : UserProfileService.profileKey(email);
  }

  bool get _isKnownMinor {
    final key = _profileKey;
    if (key != null && _sessionMinors.contains(key)) return true;
    return _birthYear != null &&
        !AgeCheckService.isAdult(_birthYear!, DateTime.now());
  }

  bool get _isUnlocked {
    final key = _profileKey;
    return key != null && _sessionAdults.contains(key);
  }

  void _openStory(Story story) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryReadScreen(
          story: story,
          profileService: widget.profileService,
        ),
      ),
    );
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Runs the age check for a locked [story]: platform signals first, the
  /// neutral birth-year screen only when there is no usable signal and no
  /// stored year. Opens the story for adults.
  Future<void> _unlock(Story story) async {
    final email = _email;
    if (email == null || _checkingStoryId != null) return;
    final key = UserProfileService.profileKey(email);
    if (_isKnownMinor) {
      _showSnackBar(AppLocalizations.of(context)!.matureStoryUnavailable);
      return;
    }
    setState(() => _checkingStoryId = story.id);
    try {
      final bool isAdult;
      switch (await _gate.resolve(email)) {
        case AgeVerdict.adult:
          isAdult = true;
        case AgeVerdict.minor:
          isAdult = false;
        case AgeVerdict.askBirthYear:
          if (!mounted) return;
          final birthYear = await Navigator.push<int>(
            context,
            MaterialPageRoute(builder: (_) => const AgeCheckScreen()),
          );
          if (birthYear == null) return;
          await _storage.setBirthYear(email: email, birthYear: birthYear);
          isAdult = AgeCheckService.isAdult(birthYear, DateTime.now());
      }

      if (isAdult) {
        _sessionAdults.add(key);
      } else {
        _sessionMinors.add(key);
      }
      if (!mounted) return;
      setState(() {});
      if (isAdult) {
        _openStory(story);
      } else {
        _showSnackBar(AppLocalizations.of(context)!.matureStoryUnavailable);
      }
    } catch (_) {
      if (!mounted) return;
      _showSnackBar(AppLocalizations.of(context)!.genericError);
    } finally {
      if (mounted) setState(() => _checkingStoryId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Background(
        opacity: 0.2,
        child: StreamBuilder<List<Story>>(
          stream: _stories,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            // Already sorted newest first by the service. Known minors
            // don't see mature stories at all, and nobody sees them before
            // the stored birth year is known.
            final hideMature = !_birthYearLoaded || _isKnownMinor;
            final stories = [
              for (final story in snapshot.data!)
                if (!(hideMature && story.mature == true)) story,
            ];
            if (stories.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: CreamCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20.0,
                      vertical: 16.0,
                    ),
                    child: Text(
                      l10n.noCompleteStories,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.ink),
                    ),
                  ),
                ),
              );
            }

            // Stories the user took part in come first, then a divider,
            // then everyone else's. Both groups keep the service's order.
            final mine = <Story>[];
            final others = <Story>[];
            for (final story in stories) {
              (story.hasPartBy(_email) ? mine : others).add(story);
            }

            // Markers stand in for the heading and the divider, so the list
            // can still be built lazily.
            final items = <Object>[
              if (mine.isNotEmpty) _ListMarker.yourStoriesHeading,
              ...mine,
              if (mine.isNotEmpty && others.isNotEmpty) _ListMarker.divider,
              ...others,
            ];

            return ListView.builder(
              padding: const EdgeInsets.all(12.0),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                switch (item) {
                  case _ListMarker.yourStoriesHeading:
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(8.0, 4.0, 8.0, 8.0),
                      child: Text(
                        l10n.yourStoriesHeading,
                        style: const TextStyle(
                          color: AppColors.primaryDark,
                          fontSize: 16.0,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  case _ListMarker.divider:
                    return const Divider(
                      height: 24.0,
                      thickness: 1.5,
                      indent: 8.0,
                      endIndent: 8.0,
                      color: AppColors.primaryDark,
                    );
                  case final Story story:
                    return _buildStoryCard(context, story);
                  default:
                    throw StateError('Unexpected list item: $item');
                }
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildStoryCard(BuildContext context, Story story) {
    final l10n = AppLocalizations.of(context)!;
    final locked = story.mature == true && !_isUnlocked;
    final unlockedMature = story.mature == true && !locked;

    final Widget tile;
    if (locked) {
      // The AI title is generated child-safe, so it is shown; the part text
      // never is, as it can contain what the review flagged. A story the
      // model refused to read has no title and falls back to the label.
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
          subtitle: Text(
            title == null
                ? l10n.authorsCount(story.parts.length)
                : '${l10n.matureStoryLockedTitle} · '
                    '${l10n.authorsCount(story.parts.length)}',
          ),
          trailing: _checkingStoryId == story.id
              ? const SizedBox(
                  width: 18.0,
                  height: 18.0,
                  child: CircularProgressIndicator(strokeWidth: 2.0),
                )
              : null,
          onTap: () => _unlock(story),
        ),
      );
    } else {
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
        subtitle: Text(l10n.authorsCount(story.parts.length)),
        trailing: unlockedMature
            ? Icon(
                Icons.lock_open,
                size: 20.0,
                semanticLabel: l10n.matureStoryAdultContent,
              )
            : null,
        onTap: () => _openStory(story),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: CreamCard(child: tile),
    );
  }
}
