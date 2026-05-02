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
      return <String, Object?>{
        'success': true,
        'mode': RestartMode.platformDefault.name,
      };
    });
  });

  tearDown(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('restartApp returns structured success result', () async {
    final result = await Restart.restartApp();

    expect(result.success, isTrue);
    expect(result.mode, RestartMode.platformDefault);
    expect(result.code, isNull);
    expect(result.message, isNull);
  });

  test('restartApp handles legacy ok response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return 'ok';
    });

    final result = await Restart.restartApp(mode: RestartMode.process);

    expect(result.success, isTrue);
    expect(result.mode, RestartMode.process);
  });

  test('restartApp returns failure on unexpected response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return 'error';
    });

    final result = await Restart.restartApp();

    expect(result.success, isFalse);
    expect(result.mode, RestartMode.platformDefault);
    expect(result.code, 'UNKNOWN_RESULT');
  });

  test('restartApp sends correct method name', () async {
    await Restart.restartApp();

    expect(log, hasLength(1));
    expect(log.first.method, 'restartApp');
  });

  test('restartApp passes default arguments', () async {
    await Restart.restartApp();

    final args = log.first.arguments as Map;
    expect(args['mode'], RestartMode.platformDefault.name);
    expect(args['webOrigin'], isNull);
    expect(args['notificationTitle'], isNull);
    expect(args['notificationBody'], isNull);
    expect(args['forceKill'], isFalse);
    expect(args['structuredResult'], isTrue);
    expect(args.containsKey('iosLegacyNotificationFallback'), isFalse);
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

  test('restartApp passes mode', () async {
    await Restart.restartApp(mode: RestartMode.flutterEngine);

    final args = log.first.arguments as Map;
    expect(args['mode'], RestartMode.flutterEngine.name);
  });

  test('restartApp passes all parameters together', () async {
    await Restart.restartApp(
      mode: RestartMode.notificationFallback,
      webOrigin: '#/home',
      notificationTitle: 'Restart',
      notificationBody: 'Tap to reopen',
      forceKill: true,
    );

    final args = log.first.arguments as Map;
    expect(args['mode'], RestartMode.notificationFallback.name);
    expect(args['webOrigin'], '#/home');
    expect(args['notificationTitle'], 'Restart');
    expect(args['notificationBody'], 'Tap to reopen');
    expect(args['forceKill'], isTrue);
  });

  test('restartApp returns structured failure on PlatformException', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'IOS_PROCESS_RESTART_UNSUPPORTED',
        message: 'iOS does not provide process restart.',
      );
    });

    final result = await Restart.restartApp(mode: RestartMode.process);

    expect(result.success, isFalse);
    expect(result.mode, RestartMode.process);
    expect(result.code, 'IOS_PROCESS_RESTART_UNSUPPORTED');
    expect(result.message, 'iOS does not provide process restart.');
  });

  test('restartCapability parses platform response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return <String, Object?>{
        'fullProcessRestart': false,
        'flutterEngineRestart': true,
        'notificationFallback': true,
        'engineRestartConfigured': true,
        'platformDefaultMode': RestartMode.flutterEngine.name,
      };
    });

    final capability = await Restart.restartCapability();

    expect(log.first.method, 'restartCapability');
    expect(capability.fullProcessRestart, isFalse);
    expect(capability.flutterEngineRestart, isTrue);
    expect(capability.notificationFallback, isTrue);
    expect(capability.engineRestartConfigured, isTrue);
    expect(capability.platformDefaultMode, RestartMode.flutterEngine);
  });

  test('restartCapability returns unavailable on PlatformException', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'Unimplemented',
        message: 'Capability unavailable.',
      );
    });

    final capability = await Restart.restartCapability();

    expect(capability.fullProcessRestart, isFalse);
    expect(capability.flutterEngineRestart, isFalse);
    expect(capability.notificationFallback, isFalse);
    expect(capability.engineRestartConfigured, isFalse);
    expect(capability.platformDefaultMode, RestartMode.platformDefault);
    expect(capability.reason, 'Capability unavailable.');
  });
}
