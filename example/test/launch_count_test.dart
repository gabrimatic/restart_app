import 'package:flutter_test/flutter_test.dart';
import 'package:restart_app_example/restart_checks.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('manual check reruns count a boot only once', () async {
    expect(await recordRestartCheckLaunch('first'), 1);
    expect(await recordRestartCheckLaunch('first'), 1);
    expect(await recordRestartCheckLaunch('second'), 2);
    expect(await recordRestartCheckLaunch('second'), 2);
  });

  test('existing example launch count is preserved', () async {
    SharedPreferences.setMockInitialValues({'launchCount': 4});
    expect(await recordRestartCheckLaunch('new-boot'), 5);
    expect(await recordRestartCheckLaunch('new-boot'), 5);
  });
}
