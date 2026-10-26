import 'package:cadavre_exquisite/data/repositories/auth/auth_repository.dart';
import 'package:cadavre_exquisite/data/repositories/safety/safety_repository.dart';
import 'package:cadavre_exquisite/domain/models/content_report.dart';
import 'package:cadavre_exquisite/domain/models/story.dart';
import 'package:cadavre_exquisite/utils/command.dart';

/// Reporting a part of the story [storyId] and blocking its author, shared
/// by the screens that show other players' writing (the story reader and
/// the chat). The owning ViewModel disposes it.
class PartSafetyActions {
  PartSafetyActions({
    required this.storyId,
    required SafetyRepository safetyRepository,
    required AuthRepository authRepository,
  })  : _safety = safetyRepository,
        _auth = authRepository {
    report = Command1<void, ({StoryPart part, ReportReason reason})>(
      (args) => _safety.report(
        storyId: storyId,
        position: args.part.position,
        reason: args.reason,
      ),
    );
    block = Command1<StoryPart, StoryPart>((part) async {
      await _safety.block(part.author);
      return part;
    });
  }

  final String storyId;
  final SafetyRepository _safety;
  final AuthRepository _auth;

  /// Reports a part to the moderators with a reason.
  late final Command1<void, ({StoryPart part, ReportReason reason})> report;

  /// Blocks a part's author: their stories disappear from every list. Its
  /// value is the part, so the View can name who was blocked.
  late final Command1<StoryPart, StoryPart> block;

  /// Whether [part] can be reported and its author blocked: not the user's
  /// own parts, nor a deleted account's anonymized ones.
  bool canActOn(StoryPart part) =>
      canReportAuthor(author: part.author, me: _auth.currentEmail);

  void dispose() {
    report.dispose();
    block.dispose();
  }
}
