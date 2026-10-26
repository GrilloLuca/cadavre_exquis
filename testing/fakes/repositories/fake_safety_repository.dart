import 'package:cadavre_exquisite/data/repositories/safety/safety_repository.dart';
import 'package:cadavre_exquisite/domain/models/content_report.dart';
import 'package:cadavre_exquisite/domain/models/email_key.dart';

/// In-memory [SafetyRepository] for ViewModel and widget tests. Starts with
/// [blocked] (emails or keys) blocked; records reports in [reports].
class FakeSafetyRepository extends SafetyRepository {
  FakeSafetyRepository({Iterable<String> blocked = const []})
      : _blocked = blocked.map(emailKey).toSet();

  Set<String> _blocked;

  /// Every report made, in order.
  final List<({String storyId, String position, ReportReason reason})> reports =
      [];

  /// When set, every call throws it.
  Object? failWith;

  void _checkFailure() {
    final failure = failWith;
    if (failure != null) throw failure;
  }

  @override
  Set<String> get blockedKeys => _blocked;

  @override
  Future<void> report({
    required String storyId,
    required String position,
    required ReportReason reason,
  }) async {
    _checkFailure();
    reports.add((storyId: storyId, position: position, reason: reason));
  }

  @override
  Future<void> block(String email) async {
    _checkFailure();
    final key = emailKey(email);
    if (_blocked.contains(key)) return;
    _blocked = {..._blocked, key};
    notifyListeners();
  }

  @override
  Future<void> unblock(String key) async {
    _checkFailure();
    _blocked = {..._blocked}..remove(key);
    notifyListeners();
  }
}
