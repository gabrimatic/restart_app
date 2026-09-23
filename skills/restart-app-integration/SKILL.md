---
name: restart-app-integration
description: >-
  Integrate or troubleshoot Flutter app restarts with restart_app, including
  restart modes, results, saved data, web routes, desktop relaunches, and
  requests from background isolates.
---

# Flutter app restart integration

## Basic usage

Import `package:restart_app/restart_app.dart` and call `Restart.restartApp()`.
It returns `Future<RestartResult>`. There is no restart widget, initialization
method, or `Restart.restart()` API.

Use the default mode unless the app needs a particular restart method. Check
`Restart.restartCapability()` when presenting a choice of modes. Its flags
report platform support; they do not guarantee that a restart will succeed.
Web supports the default restart even though its three restart flags are false.

```dart
import 'package:flutter/material.dart';
import 'package:restart_app/restart_app.dart';

Future<void> restartFromButton(BuildContext context) async {
  final result = await Restart.restartApp();
  if (!context.mounted || result.success) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(result.message ?? result.code ?? 'Could not restart the app.'),
    ),
  );
}
```

## State and errors

- If the app has unsaved changes that must survive, finish saving them through
  its existing storage code before restarting. Follow that storage API's
  durability guarantees. A failed save must not trigger a restart.
- A restart does not erase preferences, files, databases, or stored credentials.
  Do not rely on code after the restart call to finish essential work.
- Read `success`, `mode`, `code`, and `message`. Success means the platform
  accepted the request. A later native failure can leave the old app running;
  inspect native logs when startup does not run again.
- Platform errors return failed results. `MISSING_PLUGIN` means native
  registration is missing: fix registration and rebuild the app. If calling
  before `runApp`, initialize the Flutter binding before using the channel.
- Disable repeated restart actions once a request starts. Keep them disabled
  after acceptance; allow another attempt if the request fails. Check
  `context.mounted` before updating UI after an await. Do not retry in a loop.
- Overlapping requests return `RESTART_ALREADY_IN_PROGRESS` on Android and
  desktop, or `IOS_RESTART_ALREADY_IN_PROGRESS` on iOS. Wait for the existing
  request rather than switching modes.
- Send background-worker requests to the main isolate through a
  `SendPort`/`ReceivePort`. Request iOS engine restart while the app is active.

## Platform behavior

| Platform | Modes | Behavior |
| --- | --- | --- |
| Android | `platformDefault`, `process` | Default relaunches the main activity. `process` or `forceKill: true` also ends the old process. Requires an attached activity and launch intent; Android TV and Fire TV launcher entries are supported. |
| iOS | `platformDefault`, `flutterEngine`, `notificationFallback` | Default and engine modes require AppDelegate configuration. Use the bundled `restart-app-ios-engine-restart` skill. Automatic full process restart is unavailable. |
| Web | `platformDefault` | Reloads the whole Flutter web app at the same browser URL by default. `webOrigin` selects a different destination. |
| macOS | `platformDefault`, `process` | Opens a new instance through `NSWorkspace`, then asks the old instance to quit. Both modes resolve to `process`. |
| Linux | `platformDefault`, `process` | Replaces the running program through `execv` while keeping its process ID. Both modes resolve to `process`. |
| Windows | `platformDefault`, `process` | Opens a new process through `CreateProcessW` and ends the old process. Preserves the command line. Both modes resolve to `process`. |

Unsupported modes return a failure. `forceKill` only affects Android.
Notification title and body only customize the explicit iOS notification mode;
they do not select it. Never switch to notification fallback automatically when
iOS engine setup is missing.

On macOS, a termination delegate can prevent the old instance from quitting.
Windows MSIX/Store packaging can restrict standard process launching. Check
restart behavior in the app's actual distribution format.

## Web destinations

Without `webOrigin`, or with an empty value, the full browser URL stays the
same, including path, query, and hash. The Flutter app starts again; its router
decides which screen to show. Restarting at `/settings` does not navigate to `/`.

- A hash route such as `#/home` changes the fragment and reloads. It adds a
  browser history entry if the fragment changes.
- Full and relative URLs replace the current history entry. If the destination
  is the same document, it still reloads, including when its fragment changes
  or is removed.
- Relative URLs resolve against `document.baseURI`, including an HTML `base`
  element. `/` means the website root, not necessarily the Flutter app's root.

With path routing, verify that the server serves the app at the destination URL.

## Linux arguments

To keep command-line arguments, edit the app's existing
`linux/runner/main.cc` (`linux/main.cc` in older Flutter projects). Include
`<restart_app/restart_app_plugin.h>` and call
`restart_app_plugin_store_argv(argc, argv)` inside `main`, before starting Flutter.
Keep the existing runner code.

Flutter's generated plugin rules link the runner to `restart_app_plugin`.
For custom plugin wiring, ensure this link exists in `linux/CMakeLists.txt`,
after `include(flutter/generated_plugins.cmake)`:

```cmake
target_link_libraries(${BINARY_NAME} PRIVATE restart_app_plugin)
```

Without this setup, the restarted app receives only the executable argument.

## Verification

For Dart tests, mock `MethodChannel('restart')` and its `restartApp` and
`restartCapability` methods. Check request options and error UI, then clear the
mock handlers. Run the app separately to verify actual restarts.

Save a launch marker, request a restart, and confirm that startup runs again,
saved data remains, and temporary Dart state resets. On iOS, also check plugin
calls and platform views after repeated engine restarts.
