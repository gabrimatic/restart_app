# restart_app example

Demonstrates how to use `restart_app`.

The example app shows:

- `Restart.restartApp()` with structured success/error handling
- path URL strategy on web
- a UIScene iOS Flutter engine restart setup in `ios/Runner/AppDelegate.swift`
- a small Flutter package check panel that re-runs after restart

## Running

```bash
flutter pub get
flutter run
```

Use **Restart app** to dirty Dart-only state, restart, and confirm
the app returns with clean Dart state while common Flutter packages still work.

The checks cover shared preferences, package info, connectivity, URL launcher,
HTTP, cache/image loading, SVG rendering, file storage, SQLite, device info,
and WebView where the current platform supports them.

The example uses Flutter's UIScene lifecycle and registers plugins on both the
initial and replacement engines. Its `Info.plist` includes the scene manifest
required when building with Xcode 27. The explicit **iOS notification fallback**
button is the only path that schedules a notification and exits.

The example requires Dart 3.10 and Flutter 3.38 or later for the scene APIs and
its demonstration dependencies. Current Flutter releases can impose newer OS
minimums. The plugin itself retains its separate, lower SDK requirements.

A failed state write prevents restart, displays the error, and restores the
controls. A failed restart also restores the controls and clears the deliberate
Dart-only test state so another attempt can be made.

See the root [README](../README.md#ios) for the host setup matching your app.

The separate `lib/web_restart_probe.dart` entrypoint verifies actual browser
reloads and destinations. See the [runtime verification guide](../.github/ci/README.md)
for JavaScript and WebAssembly commands and the complete platform checks.
