import 'package:flutter_test/flutter_test.dart';
import 'package:restart_app_example/main.dart';

void main() {
  testWidgets('example shows restart controls', (WidgetTester tester) async {
    await tester.pumpWidget(
      const RestartAppExample(runChecksOnStart: false),
    );

    expect(find.text('Restart App Example'), findsOneWidget);
    expect(find.text('Restart app'), findsOneWidget);
    expect(find.text('Process restart'), findsOneWidget);
    expect(find.text('iOS notification fallback'), findsOneWidget);
    expect(find.text('Show capability'), findsOneWidget);
    expect(find.text('Run checks'), findsOneWidget);
  });
}
