import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restart_app/restart_app.dart';

void main() {
  const MethodChannel channel = MethodChannel('restart');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return 'ok';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('restartApp', () async {
    expect(await Restart.restartApp(), 'ok');
  });
}
