# restart_app example

Demonstrates how to use `restart_app`.

The example app shows:

- `Restart.restartApp()` with structured success/error handling
- path URL strategy on web
- opt-in iOS Flutter engine restart setup in `ios/Runner/AppDelegate.swift`
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

On iOS, the example configures a custom `FlutterEngine` factory and
re-registers plugins with `GeneratedPluginRegistrant` so
`RestartMode.platformDefault` uses Flutter engine restart. It does not use the
legacy notification fallback unless the **iOS notification fallback** button is
pressed explicitly.
