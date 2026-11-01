import 'dart:async';

import 'package:cadavre_exquisite/data/repositories/feature_flags/feature_flags_repository.dart';

/// In-memory [FeatureFlagsRepository] for ViewModel and widget tests. Starts
/// with [emailLoginOnIos]; [setEmailLoginOnIos] flips it as the console
/// would.
class FakeFeatureFlagsRepository implements FeatureFlagsRepository {
  FakeFeatureFlagsRepository({bool emailLoginOnIos = false})
      : _emailLoginOnIos = emailLoginOnIos;

  bool _emailLoginOnIos;
  final _changes = StreamController<bool>.broadcast();

  void setEmailLoginOnIos(bool value) {
    _emailLoginOnIos = value;
    _changes.add(value);
  }

  @override
  Stream<bool> watchEmailLoginOnIos() async* {
    yield _emailLoginOnIos;
    yield* _changes.stream;
  }
}
