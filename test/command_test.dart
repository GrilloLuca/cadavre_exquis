import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/utils/command.dart';

void main() {
  test('stores the value and marks completed on success', () async {
    final command = Command0<int>(() async => 42);

    await command.execute();

    expect(command.completed, isTrue);
    expect(command.value, 42);
    expect(command.error, isNull);
    expect(command.running, isFalse);
  });

  test('stores the thrown exception instead of rethrowing', () async {
    final failure = Exception('boom');
    final command = Command0<void>(() async => throw failure);

    await command.execute();

    expect(command.error, same(failure));
    expect(command.completed, isFalse);
    expect(command.running, isFalse);
  });

  test('ignores execute while running', () async {
    final gate = Completer<void>();
    var calls = 0;
    final command = Command1<void, String>((_) async {
      calls++;
      await gate.future;
    });

    final first = command.execute('a');
    expect(command.running, isTrue);
    await command.execute('b');
    gate.complete();
    await first;

    expect(calls, 1);
    expect(command.completed, isTrue);
  });

  test('notifies on start and end, clearResult resets the outcome', () async {
    final command = Command1<int, int>((x) async => throw StateError('$x'));
    var notifications = 0;
    command.addListener(() => notifications++);

    await command.execute(1);
    expect(notifications, 2);
    expect(command.error, isA<StateError>());

    command.clearResult();
    expect(command.error, isNull);
    expect(command.completed, isFalse);
    expect(notifications, 3);
  });
}
