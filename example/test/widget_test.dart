import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restart_app_example/main.dart';

void main() {
  testWidgets('Verify Platform version', (WidgetTester tester) async {
    await tester.pumpWidget(ExampleApp());

    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Text && widget.data!.startsWith('Running on:'),
      ),
      findsOneWidget,
    );
  });
}
