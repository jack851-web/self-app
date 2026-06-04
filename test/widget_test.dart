import 'package:flutter_test/flutter_test.dart';
import 'package:selfapp/app.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SelfApp());
    expect(find.text('自律'), findsOneWidget);
  });
}
