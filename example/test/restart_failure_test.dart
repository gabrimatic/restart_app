import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restart_app_example/main.dart';
import 'package:restart_app_example/restart_checks.dart';

void main() {
  const preferences = MethodChannel('plugins.flutter.io/shared_preferences');
  const restart = MethodChannel('restart');
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var failRead = false;
  var failWrite = false;
  var restartCalls = 0;

  setUp(() {
    failRead = false;
    failWrite = false;
    restartCalls = 0;
    resetRestartCheckDirtyState();
    messenger.setMockMethodCallHandler(preferences, (call) async {
      if (call.method == 'getAll') {
        if (failRead) throw PlatformException(code: 'STORAGE_UNAVAILABLE');
        return <String, Object>{};
      }
      return !failWrite;
    });
    messenger.setMockMethodCallHandler(restart, (call) async {
      restartCalls += 1;
      throw PlatformException(code: 'RESTART_FAILED', message: 'Launch failed');
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(preferences, null);
    messenger.setMockMethodCallHandler(restart, null);
  });

  testWidgets(
    'storage read failure leaves restart available without restarting',
    (tester) async {
      failRead = true;
      await tester.pumpWidget(const RestartAppExample(runChecksOnStart: false));
      await tester.tap(find.text('Restart app'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(restartCalls, 0);
      expect(restartCheckDirtyState, 0);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Restart app'),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.textContaining('STORAGE_UNAVAILABLE'), findsOneWidget);
    },
  );

  testWidgets('failed storage write prevents restart and allows retry', (
    tester,
  ) async {
    failWrite = true;
    await tester.pumpWidget(const RestartAppExample(runChecksOnStart: false));
    await tester.tap(find.text('Restart app'));
    await tester.pumpAndSettle();

    expect(restartCalls, 0);
    expect(restartCheckDirtyState, 0);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Restart app'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'native restart failure restores controls and reports the error',
    (tester) async {
      await tester.pumpWidget(const RestartAppExample(runChecksOnStart: false));
      await tester.tap(find.text('Restart app'));
      await tester.pumpAndSettle();

      expect(restartCalls, 1);
      expect(restartCheckDirtyState, 0);
      expect(find.text('RESTART_FAILED: Launch failed'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Restart app'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
}
