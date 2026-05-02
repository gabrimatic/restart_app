# restart_app

[![pub package](https://img.shields.io/pub/v/restart_app.svg)](https://pub.dev/packages/restart_app) [![likes](https://img.shields.io/pub/likes/restart_app)](https://pub.dev/packages/restart_app/score) [![popularity](https://img.shields.io/pub/popularity/restart_app)](https://pub.dev/packages/restart_app/score) [![pub points](https://img.shields.io/pub/points/restart_app)](https://pub.dev/packages/restart_app/score)

Restart or relaunch your Flutter app from Dart with one call.

Each platform uses the safest supported restart path available to Flutter apps. See [Platform behavior](#platform-behavior) for the exact native mechanism on each target.

## Quick start

Add the dependency:

```yaml
dependencies:
  restart_app: ^1.8.3
```

Import and call:

```dart
import 'package:restart_app/restart_app.dart';

await Restart.restartApp();
```

If you need to handle errors:

```dart
final result = await Restart.restartApp();

if (!result.success) {
  // Show or log result.code and result.message.
}
```

`Restart.restartApp()` is the restart API. It returns a `RestartResult` with `success`, the resolved `mode`, and platform error details when the restart cannot be started.

## Customization

Default behavior works for normal app restart flows. Pass options only when your app needs a specific platform behavior.

```dart
await Restart.restartApp(
  mode: RestartMode.platformDefault,
  webOrigin: '#/home',
  forceKill: false,
  notificationTitle: 'Restart',
  notificationBody: 'Tap to reopen the app.',
);
```

## Parameters

| Parameter | Platform | Description |
|-----------|----------|-------------|
| `mode` | All | Requested restart behavior: `platformDefault`, `flutterEngine`, `process`, or `notificationFallback`. |
| `webOrigin` | Web | Custom origin URL for the reload. Defaults to `window.origin`. Supports hash strategy (e.g. `'#/home'`). |
| `notificationTitle` | iOS | Title of the local notification shown only when `mode` is `notificationFallback`. Defaults to `Restart`. |
| `notificationBody` | iOS | Body of the local notification shown only when `mode` is `notificationFallback`. Defaults to `Tap to reopen the app.` |
| `forceKill` | Android | When `true`, fully terminates the process after launching the new activity. Defaults to `false`. `RestartMode.process` enables this path automatically on Android. |

## Platform behavior

| Platform | Mechanism | Limitations |
|----------|-----------|-------------|
| **Android** | Relaunches the main activity via `PackageManager`. Supports Android TV and Fire TV via leanback launcher fallback. `RestartMode.process` and `forceKill: true` kill the process after launch for a clean cold start. | None |
| **iOS** | Recommended: opt-in Flutter engine restart that creates a new `FlutterEngine`, runs Dart again, re-registers plugins, and replaces the root `FlutterViewController` in the same iOS process. Legacy: local notification + `exit(0)` + user tap. | iOS has no public API for automatic full process restart. Engine restart is not a process restart and cannot reset native singleton state. Legacy fallback requires notification permission and user action. |
| **Web** | Reloads the page using `window.location`. | None |
| **macOS** | Launches a new instance via `NSWorkspace` and terminates the current process. | Sandboxed (Mac App Store) builds cannot launch new instances of themselves. Returns a failed result in this case. |
| **Linux** | Replaces the current process via `execv`. Fully automatic. | None |
| **Windows** | Launches a new instance via `CreateProcess` and terminates the current process. | MSIX-packaged (Microsoft Store) apps cannot be relaunched via `CreateProcess`. |

## iOS

iOS does not provide a public API for an app to terminate itself and automatically launch a fresh process of the same app. Android-style full process restart is not available on iOS with public APIs.

`restart_app` supports two iOS behaviors:

1. **Flutter engine restart**, recommended. This keeps the iOS process alive, creates a new `FlutterEngine`, runs the Dart entrypoint again, re-registers plugins through the host app's `GeneratedPluginRegistrant`, creates a new `FlutterViewController`, replaces the active root view controller, and destroys the old engine context.
2. **Notification fallback**, legacy and explicit only. This schedules a local notification, calls `exit(0)`, and requires the user to tap the notification to reopen the app. This is not a true restart and is not recommended as normal product behavior.

### Configure Flutter engine restart

The host app owns `GeneratedPluginRegistrant`, so iOS engine restart requires one app-side setup step.

In `ios/Runner/AppDelegate.swift`:

```swift
import UIKit
import Flutter
import restart_app

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    RestartAppPlugin.configureEngineRestart { engine in
      GeneratedPluginRegistrant.register(with: engine)
    }

    GeneratedPluginRegistrant.register(with: self)

    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }
}
```

Then call:

```dart
final result = await Restart.restartApp();
```

`RestartMode.platformDefault` uses Flutter engine restart on iOS when this setup is present.
If this setup is missing, `platformDefault` fails cleanly on iOS instead of falling back to notification + `exit(0)`.

To request the engine path explicitly:

```dart
final result = await Restart.restartApp(
  mode: RestartMode.flutterEngine,
);
```

### iOS capabilities

```dart
final capability = await Restart.restartCapability();

if (capability.flutterEngineRestart) {
  await Restart.restartApp(mode: RestartMode.flutterEngine);
}
```

### What iOS engine restart resets

It resets:

- Dart root isolate
- Flutter widget tree
- Flutter engine-owned platform channels
- Flutter plugin registrations for the new engine
- Platform-view factory registrations for the new engine

It does not reset:

- The iOS process
- Swift, Objective-C, C, or C++ static/global state
- Native singleton state
- Native resources retained by plugins
- Unrelated Flutter engines or background isolates
- Native app launch lifecycle callbacks from a real process launch

For code-push systems and plugins with heavy native state, verify behavior in a real release build. Same-process engine restart is not equivalent to full process restart.

### Legacy notification fallback

Use the notification fallback only when the tradeoff is acceptable:

```dart
Restart.restartApp(
  mode: RestartMode.notificationFallback,
  notificationTitle: 'Update applied',
  notificationBody: 'Tap to reopen the app.',
);
```

The plugin requests notification permission at the moment of restart. If not already granted, iOS shows the system prompt right before exit, which feels abrupt.

Request permission earlier in your app's lifecycle. The [permission_handler](https://pub.dev/packages/permission_handler) package works well for this.

If notification permission has been denied, `restartApp()` returns a failed result.

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
