// Guards the layering described in docs/ARCHITECTURE.md by reading the
// imports of every file under lib/. A failure names the file and the import
// that breaks a rule.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Packages that talk to Firebase, Google or the device. Only the data
/// layer (and main.dart) may use them.
const _sdkPackages = [
  'package:cloud_firestore/',
  'package:firebase_auth/',
  'package:firebase_core/',
  'package:firebase_messaging/',
  'package:google_sign_in/',
  'package:shared_preferences/',
  'package:age_range_signals/',
];

/// Repository implementations and their helpers: built only in
/// lib/config/dependencies.dart, everyone else gets the interface.
final _implementation =
    RegExp(r'_(firestore|firebase|local)\.dart$|_firestore_mapping\.dart$');

/// The `import '...'` targets of [file].
List<String> _imports(File file) =>
    RegExp(r"^import '([^']+)'", multiLine: true)
        .allMatches(file.readAsStringSync())
        .map((m) => m.group(1)!)
        .toList();

/// Every Dart file under [dir], with its path relative to the project.
Map<String, List<String>> _importsUnder(String dir) => {
      for (final file in Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        file.path: _imports(file),
    };

/// The imports in [dir] matching [isViolation], as "file: import" lines.
List<String> _violations(
  String dir,
  bool Function(String import) isViolation,
) =>
    [
      for (final MapEntry(key: path, value: imports)
          in _importsUnder(dir).entries)
        for (final import in imports)
          if (isViolation(import)) '$path: $import',
    ];

bool _isSdk(String import) => _sdkPackages.any(import.startsWith);

void main() {
  test(
      'the UI uses no SDK, no data service and no repository '
      'implementation', () {
    expect(
      _violations(
        'lib/ui',
        (i) =>
            _isSdk(i) ||
            i.startsWith('package:cadavre_exquisite/data/services/') ||
            _implementation.hasMatch(i),
      ),
      isEmpty,
    );
  });

  test('the domain uses no Flutter UI, no SDK, no UI and no implementation',
      () {
    expect(
      _violations(
        'lib/domain',
        (i) =>
            _isSdk(i) ||
            i.startsWith('package:flutter/') ||
            i.startsWith('package:cadavre_exquisite/ui/') ||
            _implementation.hasMatch(i),
      ),
      isEmpty,
    );
  });

  test('the data layer never imports the UI', () {
    expect(
      _violations(
        'lib/data',
        (i) => i.startsWith('package:cadavre_exquisite/ui/'),
      ),
      isEmpty,
    );
  });

  test('repository interfaces expose no SDK types', () {
    final interfaces = _importsUnder('lib/data/repositories')
        .entries
        .where((e) => e.key.endsWith('_repository.dart'));
    expect(
      [
        for (final MapEntry(key: path, value: imports) in interfaces)
          for (final import in imports)
            if (_isSdk(import)) '$path: $import',
      ],
      isEmpty,
    );
  });

  test('the rules see the whole app', () {
    // A guard against the scans above silently finding nothing.
    expect(_importsUnder('lib/ui'), hasLength(greaterThan(20)));
    expect(_importsUnder('lib/domain'), isNotEmpty);
    expect(_importsUnder('lib/data'), isNotEmpty);
  });
}
