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
└── RestartAppPlugin.swift  # iOS implementation (Swift, UserNotifications)
```

All platforms communicate over a single `MethodChannel` named `restart`.

## Platform Notes

- **Android**: Uses `ActivityAware` to get a reference to the current activity. The `forceKill` option calls `Runtime.getRuntime().exit(0)` after 200ms.
- **iOS**: Uses `UNUserNotificationCenter` to schedule a local notification before calling `exit(0)`. Notification permission must be granted.
- **Web**: Uses `window.location.replace` or `window.location.hash` for hash-based routing.

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
