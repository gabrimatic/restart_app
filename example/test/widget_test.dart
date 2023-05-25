import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restart_app_example/main.dart';

void main() {
  testWidgets('SplashPage navigation test', (WidgetTester tester) async {
    // Build the SplashPage widget
    await tester.pumpWidget(const MaterialApp(home: SplashPage()));

    // Verify that the SplashPage contains a FlutterLogo
    expect(find.byType(FlutterLogo), findsOneWidget);

    // Wait for the navigation to HomePage
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    // Verify that the HomePage is displayed
    expect(find.text('Restart App Example'), findsOneWidget);
  });

  testWidgets('HomePage displays the Restart button',
      (WidgetTester tester) async {
    // Build the HomePage widget
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    // Verify that the HomePage contains the Restart button
    expect(find.text('Restart!'), findsOneWidget);
  });
}
