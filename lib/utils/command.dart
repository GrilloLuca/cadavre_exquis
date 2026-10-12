import 'package:flutter/foundation.dart';

/// Runs an async action for a ViewModel and exposes its state ([running],
/// [error], [completed]) to the View, adapted from the Flutter app
/// architecture guide's `Command`.
///
/// Repositories keep throwing their coded exceptions (see
/// docs/MVVM_MIGRATION.md, D1), so instead of a `Result` the command
/// catches whatever the action throws and stores it in [error]; the View
/// maps it to a localized message.
///
/// While an execution is running, further calls to `execute` are ignored,
/// so a double tap can't submit twice.
abstract class Command<T> extends ChangeNotifier {
  bool _running = false;

  /// Whether the action is running now.
  bool get running => _running;

  Object? _error;

  /// What the last execution threw, or null if it succeeded or is running.
  Object? get error => _error;

  T? _value;

  /// What the last successful execution returned.
  T? get value => _value;

  bool _completed = false;

  /// Whether the last execution finished without throwing.
  bool get completed => _completed;

  /// Forgets the outcome of the last execution, for example once the View
  /// has shown its error.
  void clearResult() {
    _error = null;
    _completed = false;
    notifyListeners();
  }

  Future<void> _execute(Future<T> Function() action) async {
    if (_running) return;

    _running = true;
    _error = null;
    _completed = false;
    notifyListeners();

    try {
      _value = await action();
      _completed = true;
    } catch (e) {
      _error = e;
    } finally {
      _running = false;
      notifyListeners();
    }
  }
}

/// A [Command] whose action takes no argument.
class Command0<T> extends Command<T> {
  Command0(this._action);

  final Future<T> Function() _action;

  Future<void> execute() => _execute(_action);
}

/// A [Command] whose action takes one argument.
class Command1<T, A> extends Command<T> {
  Command1(this._action);

  final Future<T> Function(A) _action;

  Future<void> execute(A argument) => _execute(() => _action(argument));
}
