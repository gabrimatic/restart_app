import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restart_app/restart_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('restart');
  final log = <MethodCall>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return 'ok';
    });
  });

  tearDown(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('restartApp returns true on success', () async {
    final result = await Restart.restartApp();
    expect(result, isTrue);
  });

  test('restartApp returns false on non-ok response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return 'error';
    });

    final result = await Restart.restartApp();
    expect(result, isFalse);
  });

  test('restartApp sends correct method name', () async {
    await Restart.restartApp();
    expect(log, hasLength(1));
    expect(log.first.method, 'restartApp');
  });

  test('restartApp passes default arguments', () async {
    await Restart.restartApp();
    final args = log.first.arguments as Map;
    expect(args['webOrigin'], isNull);
    expect(args['notificationTitle'], isNull);
    expect(args['notificationBody'], isNull);
    expect(args['forceKill'], isFalse);
  });

  test('restartApp passes webOrigin', () async {
    await Restart.restartApp(webOrigin: 'http://example.com');
    final args = log.first.arguments as Map;
    expect(args['webOrigin'], 'http://example.com');
  });

  test('restartApp passes iOS notification parameters', () async {
    await Restart.restartApp(
      notificationTitle: 'Title',
      notificationBody: 'Body',
    );
    final args = log.first.arguments as Map;
    expect(args['notificationTitle'], 'Title');
    expect(args['notificationBody'], 'Body');
  });

  test('restartApp passes forceKill', () async {
    await Restart.restartApp(forceKill: true);
    final args = log.first.arguments as Map;
    expect(args['forceKill'], isTrue);
  });

  test('restartApp passes all parameters together', () async {
    await Restart.restartApp(
      webOrigin: '#/home',
      notificationTitle: 'Restart',
      notificationBody: 'Tap to reopen',
      forceKill: true,
    );
    final args = log.first.arguments as Map;
    expect(args['webOrigin'], '#/home');
    expect(args['notificationTitle'], 'Restart');
    expect(args['notificationBody'], 'Tap to reopen');
    expect(args['forceKill'], isTrue);
  });
}
