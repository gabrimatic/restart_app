# restart_app

[![pub package](https://img.shields.io/pub/v/restart_app.svg)](https://pub.dev/packages/restart_app) [![likes](https://img.shields.io/pub/likes/restart_app)](https://pub.dev/packages/restart_app/score) [![popularity](https://img.shields.io/pub/popularity/restart_app)](https://pub.dev/packages/restart_app/score) [![pub points](https://img.shields.io/pub/points/restart_app)](https://pub.dev/packages/restart_app/score)

Restart your Flutter app with a single function call. Works on Android, iOS, web, macOS, Linux, and Windows using native APIs on each platform.

## Quick start

Add the dependency:

```yaml
dependencies:
  restart_app: ^1.7.0
```

Import and call:

```dart
import 'package:restart_app/restart_app.dart';

final restarted = await Restart.restartApp();
```

Returns `true` if the restart was initiated. Returns `false` on failure (permission denied, missing executable, no launchable activity).

## Parameters

| Parameter | Platform | Description |
|-----------|----------|-------------|
| `webOrigin` | Web | Custom origin URL for the reload. Defaults to `window.origin`. Supports hash strategy (e.g. `'#/home'`). |
| `notificationTitle` | iOS | Title of the local notification shown after exit. |
| `notificationBody` | iOS | Body of the local notification shown after exit. |
| `forceKill` | Android | When `true`, fully terminates the process after launching the new activity. Defaults to `false`. |

## Platform behavior

| Platform | Mechanism | Limitations |
|----------|-----------|-------------|
| **Android** | Relaunches the main activity via `PackageManager`. Supports Android TV and Fire TV via leanback launcher fallback. With `forceKill: true`, kills the process after launch for a clean cold start. | None |
| **iOS** | Schedules a local notification, then exits via `exit(0)`. Tap the notification to reopen. Not a fully automatic restart. | Requires notification permission. Apple's App Store guidelines discourage `exit()`. |
| **Web** | Reloads the page using `window.location`. | None |
| **macOS** | Launches a new instance via `NSWorkspace` and terminates the current process. | Sandboxed (Mac App Store) builds cannot launch new instances of themselves. Returns `false` in this case. |
| **Linux** | Replaces the current process via `execv`. Fully automatic. | None |
| **Windows** | Launches a new instance via `CreateProcess` and terminates the current process. | MSIX-packaged (Microsoft Store) apps cannot be relaunched via `CreateProcess`. |

## iOS

### Notification content

Customize what's shown after the app exits:

```dart
Restart.restartApp(
  notificationTitle: 'Update applied',
  notificationBody: 'Tap to reopen the app.',
);
```

### Notification permission

The plugin requests notification permission at the moment of restart. If not already granted, iOS shows the system prompt right before exit, which feels abrupt.

Request permission earlier in your app's lifecycle. The [permission_handler](https://pub.dev/packages/permission_handler) package works well for this.

If notification permission has been denied, `restartApp()` returns `false`.

### Provisioning profiles

`restart_app` uses **local notifications only**, not push notifications. It adds no push-related entitlements to your app.

If you see `"requires a provisioning profile with the Push Notifications feature"` when exporting an IPA, another dependency is the cause (commonly `firebase_messaging`). Add the Push Notifications capability to your distribution provisioning profile.

## Linux

### Command-line arguments

By default, the restarted process launches without the original command-line arguments. To preserve them, call `restart_app_plugin_store_argv` in your `linux/main.cc` before running the Flutter engine:

```cpp
#include <restart_app/restart_app_plugin.h>

int main(int argc, char** argv) {
  restart_app_plugin_store_argv(argc, argv);
  // ... rest of main()
}
```

Most Flutter apps don't rely on command-line arguments, so this step is optional.

## Background isolates

`Restart.restartApp()` uses a platform channel and must run on the **main isolate**. Calling it from a background isolate throws:

```
Bad state: The BackgroundIsolateBinaryMessenger.instance value is invalid
until BackgroundIsolateBinaryMessenger.ensureInitialized is executed.
```

Send a message from your isolate to the main isolate instead:

```dart
// Main isolate: listen for restart signals
final receivePort = ReceivePort();
receivePort.listen((message) {
  if (message == 'restart') {
    Restart.restartApp();
  }
});

// Spawn the isolate with the SendPort
await Isolate.spawn(myIsolateFunction, receivePort.sendPort);

// Background isolate: signal instead of calling restartApp() directly
void myIsolateFunction(SendPort sendPort) {
  // ... your background work ...
  sendPort.send('restart');
}
```

## Requirements

**Dart SDK:** `>=3.4.0` · **Flutter:** `>=3.22.0`

## Author

Created by [Soroush Yousefpour](https://gabrimatic.info)

<a href="https://www.buymeacoffee.com/gabrimatic" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Book" style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;-webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;" ></a>
