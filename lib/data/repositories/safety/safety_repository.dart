import 'package:flutter/foundation.dart';

import 'package:cadavre_exquisite/domain/models/content_report.dart';

/// Reporting objectionable parts and blocking their authors, for the
/// signed-in user. Notifies listeners whenever [blockedKeys] changes, so the
/// story lists can hide blocked authors' stories straight away.
/// The actions complete as soon as the change is made locally, without
/// waiting for the server (offline it's sent once back online); they throw
/// only when nobody is signed in.
abstract class SafetyRepository extends ChangeNotifier {
  /// The email keys (see `emailKey`) of the authors the signed-in user
  /// blocked. Empty while signed out and until the list has loaded.
  Set<String> get blockedKeys;

  /// Reports the part at [position] of the story [storyId] to the
  /// moderators.
  Future<void> report({
    required String storyId,
    required String position,
    required ReportReason reason,
  });

  /// Blocks the author with [email]: their stories are no longer shown to
  /// the signed-in user. Blocking someone already blocked does nothing.
  Future<void> block(String email);

  /// Unblocks the author whose email key is [key].
  Future<void> unblock(String key);
}
