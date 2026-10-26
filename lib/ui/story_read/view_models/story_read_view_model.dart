import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/safety/safety_repository.dart';
import 'package:cadavre_exquisite/data/repositories/user_profile/user_profile_repository.dart';
import 'package:cadavre_exquisite/domain/models/author_name.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/ui/core/view_models/part_safety_actions.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// A completed story to read, with its authors' nicknames, and reporting
/// its parts or blocking their authors ([safety]).
class StoryReadViewModel extends ChangeNotifier {
  StoryReadViewModel({
    required this.story,
    required UserProfileRepository profileRepository,
    required SafetyRepository safetyRepository,
    required AuthRepository authRepository,
  })  : _profiles = profileRepository,
        safety = PartSafetyActions(
          storyId: story.id,
          safetyRepository: safetyRepository,
          authRepository: authRepository,
        ) {
    loadNicknames = Command0<void>(_loadNicknames)..execute();
  }

  final Story story;
  final UserProfileRepository _profiles;

  /// Reporting a part and blocking its author.
  final PartSafetyActions safety;

  /// Fetches the authors' nicknames. Started on creation; never fails: a
  /// failed lookup leaves that author without a nickname.
  late final Command0<void> loadNicknames;

  Map<String, String> _nicknames = const {};

  Future<void> _loadNicknames() async {
    try {
      _nicknames =
          await _profiles.nicknamesFor(story.parts.map((p) => p.author));
    } catch (_) {
      _nicknames = const {};
    }
  }

  /// The name to show for the author of [part]: their nickname once loaded,
  /// otherwise the masked email; null if neither is usable.
  String? authorNameOf(StoryPart part) =>
      authorDisplayName(nickname: _nicknames[part.author], email: part.author);

  @override
  void dispose() {
    loadNicknames.dispose();
    safety.dispose();
    super.dispose();
  }
}
