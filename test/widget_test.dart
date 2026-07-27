import 'package:flutter_test/flutter_test.dart';
import 'package:cmdclip/main.dart';

void main() {
  testWidgets('CmdClipApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const CmdClipApp());

    // Verify that the initial page renders correctly.
    // It should display 'Clipboard History' in the app bar or similar text.
    expect(find.text('Clipboard History'), findsOneWidget);
  });
}
