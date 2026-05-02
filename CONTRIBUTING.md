# Contributing

Bug fixes, platform improvements, better docs. Here's how to get involved.

## Dev Setup

```bash
git clone https://github.com/gabrimatic/restart_app.git
cd restart_app
flutter pub get
cd example && flutter pub get
```

Run the example app on your target platform:

```bash
flutter run -d <device>
```

## Architecture

```
lib/
├── restart_app.dart     # public Dart API, MethodChannel
└── restart_web.dart     # web platform implementation

android/src/main/kotlin/gabrimatic/info/restart/
└── RestartPlugin.kt     # Android implementation (Kotlin)

ios/restart_app/Sources/restart_app/
└── RestartAppPlugin.swift  # iOS implementation (Swift, FlutterEngine, UserNotifications fallback)

linux/
└── restart_app_plugin.cc   # Linux implementation (execv)

macos/restart_app/Sources/restart_app/
└── RestartAppPlugin.swift  # macOS implementation (NSWorkspace)

windows/
└── restart_app_plugin.cpp  # Windows implementation (CreateProcessW)
```

All platforms communicate over a single `MethodChannel` named `restart`.

## Platform Notes

- **Android**: Uses `ActivityAware` to get a reference to the current activity. It relaunches the main activity with package-manager launcher intents. The `forceKill` option terminates the old process after the new activity starts.
- **iOS**: iOS has no public API for automatic full process restart. The recommended path is opt-in Flutter engine restart: the host app provides plugin registration, the plugin creates a fresh `FlutterEngine`, runs Dart again, replaces the root `FlutterViewController`, and destroys the old engine context. The notification + `exit(0)` flow remains only as a legacy fallback.
- **Web**: Uses `window.location.replace` or `window.location.hash` for hash-based routing.
- **macOS**: Uses `NSWorkspace` to launch a new app instance, then terminates the current process.
- **Linux**: Uses `execv` to replace the current process.
- **Windows**: Uses `CreateProcessW` to launch a new instance, then exits the current process.

## PR Checklist

- One feature or fix per PR. Keep scope tight.
- `flutter analyze` must pass with no issues.
- Test on the affected platform(s) before opening.
- Update `CHANGELOG.md` if the change is user-facing.
- Do not bump version numbers — that is handled during release.
- Match existing code style. No reformatting unrelated files.

## Reporting Issues

Use the [bug report template](https://github.com/gabrimatic/restart_app/issues/new?template=bug_report.md). Include your Flutter version, target platform, and steps to reproduce.

## Vulnerability Reporting

See [SECURITY.md](SECURITY.md). Do **not** open public issues for security vulnerabilities.
