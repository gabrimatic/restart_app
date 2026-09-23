---
name: restart-app-integration
description: >-
  Integrate or troubleshoot Flutter app restarts with restart_app, including
  restart modes, structured results, web routes, desktop relaunches, and
  requests from background isolates.
---

# Integrate restart_app

## API and lifecycle

- Import `package:restart_app/restart_app.dart`. Use
  `Restart.restartApp()`, which returns `Future<RestartResult>`, not a boolean.
  Do not invent `Restart.restart()`, a restart widget, or an initialization API.
- Prefer the default mode. Select an explicit mode only for a supported target.
  Read `Restart.restartCapability()` when the UI needs to offer specific modes.
  Its flags describe platform support, not a guarantee that the next call will
  succeed. Web supports default reload even though all three restart flags are
  false.
- Persist required state and await pending writes **before** requesting restart.
  Restart does not clear preferences, databases, files, or authentication.
  Do not depend on code after the call to complete essential work.
- Inspect `result.success`, `result.mode`, `result.code`, and `result.message`.
  Success means accepted and initiated, not proof that the replacement app ran.
  Deferred native failures can occur after success; inspect native logs and
  verify a new launch or engine boot when debugging.
- Platform errors become failed results. `MissingPluginException` and Flutter
  binding errors are not caught by this API. Fix plugin registration, rebuild
  after adding native dependencies, or initialize the Flutter binding when
  invoking channels before `runApp`; do not silently retry a missing plugin.
- Route background-worker restart signals to the main isolate using a
  `SendPort`/`ReceivePort`. Request iOS engine restart while the app is active.
- Prevent repeated taps while a restart is pending. Check `context.mounted`
  before updating UI after an await. Do not create an automatic restart loop.

## Example

Call this from an app action on the main isolate. Supply the app's existing
persistence function; a save failure must prevent the restart.

```dart
import 'package:flutter/material.dart';
import 'package:restart_app/restart_app.dart';

Future<void> saveAndRestart(
  BuildContext context,
  Future<void> Function() savePendingChanges,
) async {
  await savePendingChanges();
  final result = await Restart.restartApp();
  if (!context.mounted || result.success) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(result.message ?? result.code ?? 'Restart could not start.'),
    ),
  );
}
```

Handle save errors in the caller's normal error UI. Disable its restart action
while this operation is pending.

## Platform decisions

| Target | Supported modes | Integration details |
| --- | --- | --- |
| Android | `platformDefault`, `process` | Default relaunches the launcher activity. `process` or `forceKill: true` additionally terminates the old process. A foreground activity and launch intent are required; TV uses a leanback fallback. |
| iOS | Configured `platformDefault`, `flutterEngine`; explicit `notificationFallback` | Default requires native engine setup. Read the bundled `restart-app-ios-engine-restart` skill for host integration. Full process restart is unsupported. |
| Web | `platformDefault` only | Null or empty `webOrigin` reloads the current URL and keeps its route. `#/home` changes the hash and reloads. Other nonempty values use location replacement; relative URLs resolve against the current page. Do not request `process`. |
| macOS | `platformDefault`, `process` | Resolves to `process`. Uses `NSWorkspace` to launch a new instance, then terminates the old one. Check actual distribution and sandbox constraints. |
| Linux | `platformDefault`, `process` | Resolves to `process`. Uses `execv`; the PID can stay the same. Preserve arguments as described below when needed. |
| Windows | `platformDefault`, `process` | Resolves to `process`. Uses `CreateProcessW` and retains the command line. MSIX/Store packaging can prevent relaunch. |

Unsupported modes fail instead of silently choosing another mode. `forceKill`
is Android-only. Notification title/body only customize the explicit iOS
notification fallback; they do not enable it. Never substitute notification
fallback automatically after iOS engine setup fails.

For Linux apps that need their original arguments, add the following call to
existing `linux/main.cc`, before starting the Flutter engine:

Include `<restart_app/restart_app_plugin.h>` and call
`restart_app_plugin_store_argv(argc, argv)` inside the existing
`main(int argc, char** argv)`. Keep the runner code. Without this opt-in, Linux
restarts with only the executable argument.

## Verification

Mock `MethodChannel('restart')` for Dart tests to assert requested options and
success/error UI without restarting the test runner. Native methods are
`restartApp` and `restartCapability`. Clear mock handlers after each test.
Mocks do not prove native restart behavior.

Run the actual target app, persist a launch marker, request restart, and check
that startup runs again. Verify saved state survives and temporary Dart state
resets. On iOS also verify plugin channels and platform views after repeated
engine restarts. Test the distribution build when packaging affects relaunch.
