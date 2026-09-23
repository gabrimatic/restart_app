@TestOn('browser')
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restart_app/restart_web.dart';

/// Records restart requests instead of navigating, so the method-channel
/// contract can be asserted without reloading the test page.
class _RecordingRestartWeb extends RestartWeb {
  final List<String?> restartCalls = <String?>[];

  @override
  String restart(String? webOrigin) {
    restartCalls.add(webOrigin);
    return 'ok';
  }
}

void main() {
  late _RecordingRestartWeb plugin;

  setUp(() {
    plugin = _RecordingRestartWeb();
  });

  test('restartCapability reports web behavior', () async {
    final result = await plugin.handleMethodCall(
      const MethodCall('restartCapability'),
    );

    expect(result, {
      'fullProcessRestart': false,
      'flutterEngineRestart': false,
      'notificationFallback': false,
      'engineRestartConfigured': false,
      'platformDefaultMode': 'platformDefault',
      'reason': 'Web restart reloads the Flutter app at the same browser URL.',
    });
  });

  test('restartApp reloads with null origin by default', () async {
    final result = await plugin.handleMethodCall(
      const MethodCall('restartApp', {'mode': 'platformDefault'}),
    );

    expect(result, 'ok');
    expect(plugin.restartCalls, [null]);
  });

  test('restartApp returns structured result when requested', () async {
    final result = await plugin.handleMethodCall(
      const MethodCall('restartApp', {
        'mode': 'platformDefault',
        'structuredResult': true,
      }),
    );

    expect(result, {'success': true, 'mode': 'platformDefault'});
    expect(plugin.restartCalls, [null]);
  });

  test('restartApp passes webOrigin through', () async {
    await plugin.handleMethodCall(
      const MethodCall('restartApp', {
        'mode': 'platformDefault',
        'webOrigin': '#/home',
      }),
    );

    expect(plugin.restartCalls, ['#/home']);
  });

  test('restartApp defaults to platformDefault without arguments', () async {
    final result = await plugin.handleMethodCall(
      const MethodCall('restartApp'),
    );

    expect(result, 'ok');
    expect(plugin.restartCalls, [null]);
  });

  test('restartApp rejects unsupported modes without navigating', () async {
    for (final mode in ['process', 'flutterEngine', 'notificationFallback']) {
      await expectLater(
        plugin.handleMethodCall(MethodCall('restartApp', {'mode': mode})),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'UNSUPPORTED_RESTART_MODE',
          ),
        ),
      );
    }

    expect(plugin.restartCalls, isEmpty);
  });

  test('unknown methods throw Unimplemented', () async {
    await expectLater(
      plugin.handleMethodCall(const MethodCall('doesNotExist')),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'Unimplemented',
        ),
      ),
    );
  });
}
