# Restart verification

A successful method-channel result means that a restart was accepted. It does
not prove that a replacement engine or application completed startup. These
checks run consumer applications and require evidence from the new launch.

## SDK compatibility

With the desired Flutter SDK on `PATH`, run:

```sh
python3 .github/ci/check_compatibility.py --expected-flutter 3.22.0 --expected-dart 3.4
```

This resolves the package as a path dependency, runs the public API regression
suite using that SDK, analyzes the consumer, and builds its web application.
The package's development-tool constraints do not apply to the consumer.
CI repeats this on the minimum, transitional, and current SDKs.

Apple builds separately verify CocoaPods and SwiftPM participation in the
generated dependency graph. The legacy SwiftPM check uses Flutter 3.27, where
the experimental integration is available on stable. Flutter 3.24 stable
ignores the SwiftPM feature option. The plugin retains its original SwiftPM
manifest to support both generations. Current Flutter may warn about the
newer `FlutterFramework` dependency declaration; adding it unconditionally
would break older hosts whose generated graph does not provide that package.

## Android

Build a fresh probe with a current Flutter SDK:

```sh
python3 .github/ci/build_android_consumer.py /tmp/restart_android_current --target-sdk 37 --compile-minor 0
python3 .github/ci/run_android_proof.py /tmp/restart_android_current/build/app/outputs/flutter-apk/app-debug.apk --serial emulator-5554
```

For Android 21, put Flutter 3.22.0 on `PATH` and build with
`--minimum --target-sdk 34` instead. The minimum consumer updates the old app
template to the package's Java 17, AGP 8, and Kotlin 2 requirements. Current
Flutter itself requires newer Android versions even though the plugin keeps
its Android 21 minimum.

The runner installs and clears only the disposable
`com.example.restart_android_proof` app. It requires 15 successful restarts,
cycling through consecutive defaults, explicit process, and force-kill requests.
Each launch checks persisted state, fresh Dart state, process behavior, rejected
modes, and eight rejected concurrent native requests. The next launch also checks
that the preceding duplicate-request assertions completed. The collector rejects
stale UI dumps and launch histories. It saves a JSON report and a screenshot.
Use a dedicated emulator or test device.
The example app separately exercises shared preferences, SQLite, file storage,
networking, platform views, and other plugins before and after restart.

## Desktop

Create a Flutter desktop consumer, add a path dependency on this checkout, and
copy `restart_proof_main.dart` into its `lib/main.dart`. Before building Linux,
wire the generated runner's original command-line arguments:

```sh
python3 .github/ci/prepare_linux_proof.py /path/to/consumer
```

Build the application, then pass its executable or macOS `.app` to the runner:

```sh
python3 .github/ci/run_desktop_proof.py /path/to/restart_proof.app
```

On Linux, run the command under `xvfb-run -a` if no display is available. CI
builds and runs all three desktop consumers. The runner clears only its named
proof files, supplies a unique run ID, and requires ten native restarts,
eleven launches, both rejected modes, concurrent-request rejection, saved state,
and fresh Dart state. Windows and Linux must preserve an argument containing
spaces, quotes, and Unicode. Linux also checks preflight failure and an accepted
restart whose `execv` fails with an invalid executable, then restores the test
binary and requires a successful retry. The runner restores its own backup if
the test is interrupted. macOS
and Windows must change PID; Linux `execv` retains PID. The runner stops only
processes whose executable identity matches its disposable application and
writes a JSON report.

The separate Windows native harness injects launch, event, worker, wait, and
resume failures, checks resource cleanup, and confirms later requests recover:

```sh
cmake -S windows/tests -B /path/to/native-tests
cmake --build /path/to/native-tests --config Release
ctest --test-dir /path/to/native-tests -C Release --output-on-failure
```

## iOS

Use the example with its UIScene host configuration. Repeatedly request both
default and explicit engine restart. Confirm a new boot token, `dirty=0`, saved
launch counts, and successful plugin checks. The native process should remain
alive. Also background and foreground the app between attempts.

Run `RunnerTests` on an iOS simulator through the example's Xcode workspace.
These tests cover unsupported modes, concurrent engine and notification
requests, notification failure recovery, foreground scene selection, factory
failure without destroying the current engine, custom-window unavailability,
and restoring root-controller protection after reconfiguration.

Test notification fallback separately. Denied permission must report failure
without exiting. Accepted fallback exits and requires the user to reopen the
app through its notification. It is not an automatic process relaunch.

## Web

From `example/`, build `lib/web_restart_probe.dart` as the entrypoint:

```sh
flutter build web -t lib/web_restart_probe.dart
```

From the repository root, serve the output:

```sh
python3 .github/ci/serve_web_probe.py example/build/web
```

Visit `/deep/start?case=default&run=<unique-id>#existing`. Repeat with `empty`,
`hash`, `full`, `relative`, and `unsupported`. Every case must display `PASS`.
Use a new run ID for every test batch so saved results cannot satisfy another
run. Repeat after building with `--wasm`, and confirm the browser loads
`main.dart.wasm`. The probe uses the example's root HTML base URL and the server
provides route fallback. It checks actual document replacement and persistent
versus in-memory state, not a mocked navigation call.

## Documentation

```sh
node --test doc/scripts/prepare-github-pages.test.mjs
```

Validate, export, and prepare the docs using the Pages workflow commands. In
the served export, verify search (including no results), result navigation,
exact code copying, saved appearance, mobile navigation, and keyboard dismissal.
The export uses local controls and a generated search index because hosted
Mintlify interaction scripts do not run on GitHub Pages.

## Release evidence

Record the SDK, OS, build mode, app target SDK, packaging, and actual scenarios.
A simulator run does not establish physical-device or OEM behavior. A desktop
CI application does not establish signed Store/MSIX behavior, every Linux
distribution, custom termination delegates, or every host application's plugin
lifecycle. Test the application and distribution format you ship.
