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
enum _ListMarker { yourStoriesHeading, divider, matureStoriesEntry }

class CompleteStoriesScreen extends StatelessWidget {
  /// Language code of the room the user has joined: only stories in this
  /// language are listed.
  final String language;

  /// Id of the private room the user has joined, if any. When set, this
  /// takes precedence over [language]: only stories in this room are listed.
  final String? roomId;

  /// Whether to list the stories the AI review flagged as unsuitable for
  /// children instead of the others. The mature list is only reachable
  /// through the age check (see [_MatureStoriesEntry]).
  final bool mature;

  /// Source of the stories. Defaults to a [StoryService] on the default
  /// Firestore instance; injectable for tests.
  final StoryService? storyService;

  /// Decides access to the mature list. Defaults to [AgeGate]; injectable
  /// for tests.
  final AgeGate? ageGate;

  /// Stores the birth year asked when [ageGate] has no answer. Defaults to
  /// [AgeCheckService]; inject the same storage as [ageGate] in tests.
  final AgeCheckService? ageCheckService;

  /// Email of the signed-in user. Defaults to the current [FirebaseAuth]
  /// user's; when provided, [FirebaseAuth] is never accessed.
  final String? email;

  const CompleteStoriesScreen({
    super.key,
    required this.language,
    this.roomId,
    this.mature = false,
    this.storyService,
    this.ageGate,
    this.ageCheckService,
    this.email,
  });

  /// Forgets the users hidden from the mature entry this session.
  @visibleForTesting
  static void clearSessionState() =>
      _MatureStoriesEntryState._sessionMinors.clear();

  @override
  Widget build(BuildContext context) {
    final storyService = this.storyService ?? StoryService();
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Background(
        opacity: 0.2,
        child: StreamBuilder<List<Story>>(
          stream: storyService.completeStoriesStream(
            language: language,
            roomId: roomId,
            mature: mature,
          ),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final stories = snapshot.data!;
            if (stories.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CreamCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20.0,
                          vertical: 16.0,
                        ),
                        child: Text(
                          mature
                              ? l10n.noMatureStories
                              : l10n.noCompleteStories,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.ink),
                        ),
                      ),
                      if (!mature) ...[
                        const SizedBox(height: 8.0),
                        _matureStoriesEntry(),
                      ],
                    ],
                  ),
                ),
              );
            }

            // Stories the user took part in come first, then a divider,
            // then everyone else's.
            final email =
                this.email ?? FirebaseAuth.instance.currentUser?.email;
            final mine = <Story>[];
            final others = <Story>[];
            for (final story in stories) {
              (story.hasPartBy(email) ? mine : others).add(story);
            }

            // Markers stand in for the heading and the divider, so the list
            // can still be built lazily.
            final items = <Object>[
              if (mine.isNotEmpty) _ListMarker.yourStoriesHeading,
              ...mine,
              if (mine.isNotEmpty && others.isNotEmpty) _ListMarker.divider,
              ...others,
              if (!mature) _ListMarker.matureStoriesEntry,
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
                  case _ListMarker.matureStoriesEntry:
                    return Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: _matureStoriesEntry(),
                    );
                  case Story story:
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

  Widget _matureStoriesEntry() => _MatureStoriesEntry(
        language: language,
        roomId: roomId,
        storyService: storyService,
        ageGate: ageGate,
        ageCheckService: ageCheckService,
        email: email,
      );

  Widget _buildStoryCard(BuildContext context, Story story) {
    final l10n = AppLocalizations.of(context)!;
    final preview = story.parts.isNotEmpty ? story.parts.first.text : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: CreamCard(
        child: ListTile(
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
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StoryReadScreen(story: story),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Opens the stories flagged as mature once [AgeGate] lets the user in:
/// platform age signals first, the neutral birth-year screen only when
/// there is no usable signal and no stored year. Hidden once the user is
/// known to be a minor.
class _MatureStoriesEntry extends StatefulWidget {
  final String language;
  final String? roomId;
  final StoryService? storyService;
  final AgeGate? ageGate;
  final AgeCheckService? ageCheckService;
  final String? email;

  const _MatureStoriesEntry({
    required this.language,
    this.roomId,
    this.storyService,
    this.ageGate,
    this.ageCheckService,
    this.email,
  });

  @override
  State<_MatureStoriesEntry> createState() => _MatureStoriesEntryState();
}

class _MatureStoriesEntryState extends State<_MatureStoriesEntry> {
  /// Users found to be minors this app session (profile keys), so the
  /// entry stays hidden even when the list is rebuilt from scratch.
  static final Set<String> _sessionMinors = {};

  late final AgeCheckService _storage =
      widget.ageCheckService ?? AgeCheckService();
  late final AgeGate _gate = widget.ageGate ?? AgeGate(storage: _storage);
  String? _email;
  int? _birthYear;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _email = widget.email ?? FirebaseAuth.instance.currentUser?.email;
    _loadBirthYear();
  }

  /// Quietly reads the stored birth year, to hide the entry from known
  /// minors. Never asks the platform: that may show a system sheet, so it
  /// only happens on tap.
  Future<void> _loadBirthYear() async {
    final email = _email;
    if (email == null) return;
    try {
      final birthYear = await _gate.storedBirthYear(email);
      if (mounted) setState(() => _birthYear = birthYear);
    } catch (_) {
      // Unknown age: the entry stays visible and the check runs on tap.
    }
  }

  bool get _isKnownMinor {
    final email = _email;
    if (email != null &&
        _sessionMinors.contains(UserProfileService.profileKey(email))) {
      return true;
    }
    return _birthYear != null &&
        !AgeCheckService.isAdult(_birthYear!, DateTime.now());
  }

  Future<void> _open() async {
    final email = _email;
    if (email == null || _isChecking) return;
    setState(() => _isChecking = true);
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
      if (!mounted) return;

      final l10n = AppLocalizations.of(context)!;
      if (!isAdult) {
        _sessionMinors.add(UserProfileService.profileKey(email));
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.matureStoriesUnavailable)),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: Text(l10n.matureStoriesTitle),
              backgroundColor: AppColors.primary,
            ),
            body: CompleteStoriesScreen(
              language: widget.language,
              roomId: widget.roomId,
              mature: true,
              storyService: widget.storyService,
              ageGate: widget.ageGate,
              ageCheckService: widget.ageCheckService,
              email: widget.email,
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.genericError)),
      );
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isKnownMinor) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return CreamCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 4.0,
        ),
        iconColor: AppColors.primary,
        textColor: AppColors.ink,
        leading: const Icon(Icons.lock_outline),
        title: Text(
          l10n.matureStoriesEntryTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(l10n.matureStoriesEntrySubtitle),
        trailing: _isChecking
            ? const SizedBox(
                width: 18.0,
                height: 18.0,
                child: CircularProgressIndicator(strokeWidth: 2.0),
              )
            : const Icon(Icons.chevron_right),
        onTap: _open,
      ),
    );
  }
}
