// Basic smoke test: the welcome screen should show the app name and the
// Log In / Register entry points.

import 'package:flutter_test/flutter_test.dart';

import 'package:cadavre_exquisite/main.dart';

void main() {
  testWidgets('Welcome screen shows app name and auth buttons',
      (WidgetTester tester) async {
    await tester.pumpWidget(const CadavreExquisiteApp());
    await tester.pump();

    expect(find.text('Cadavre Exquisite'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
  });
}
