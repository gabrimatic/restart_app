# restart_app

[![pub package](https://img.shields.io/pub/v/restart_app.svg)](https://pub.dev/packages/restart_app) [![likes](https://img.shields.io/pub/likes/restart_app)](https://pub.dev/packages/restart_app/score) [![popularity](https://img.shields.io/pub/popularity/restart_app)](https://pub.dev/packages/restart_app/score) [![pub points](https://img.shields.io/pub/points/restart_app)](https://pub.dev/packages/restart_app/score)

Restart your Flutter app with a single function call. Works on Android, iOS, web, and macOS using native APIs on each platform.

## Quick start

Add the dependency:

```yaml
dependencies:
  restart_app: ^1.6.0
```

Import and call:

```dart
import 'package:restart_app/restart_app.dart';

Restart.restartApp();
```

## Parameters

| Parameter | Platform | Description |
|-----------|----------|-------------|
| `webOrigin` | Web | Custom origin URL for the reload. Defaults to `window.origin`. Supports hash strategy (e.g. `'#/home'`). |
| `notificationTitle` | iOS | Title of the local notification shown after exit. |
| `notificationBody` | iOS | Body of the local notification shown after exit. |
| `forceKill` | Android | When `true`, fully terminates the process after launching the new activity. Defaults to `false`. |

## Platform behavior

| Platform | Mechanism |
|----------|-----------|
| **Android** | Relaunches the main activity via `PackageManager`. With `forceKill: true`, kills the process after launch for a clean cold start. |
| **iOS** | Schedules a local notification, then exits via `exit(0)`. Tap the notification to reopen. Not a fully automatic restart. |
| **Web** | Reloads the page using `window.location`. |
| **macOS** | Launches a new instance via `NSWorkspace` and terminates the current process. Fully automatic. |

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

If notification permission has been denied, `restartApp()` throws a `PlatformException` with code `NOTIFICATION_DENIED`:

```dart
try {
  await Restart.restartApp();
} on PlatformException catch (e) {
  if (e.code == 'NOTIFICATION_DENIED') {
    // Prompt the user to enable notifications in Settings
  }
}
```

### Provisioning profiles

`restart_app` uses **local notifications only**, not push notifications. It adds no push-related entitlements to your app.

If you see `"requires a provisioning profile with the Push Notifications feature"` when exporting an IPA, another dependency is the cause (commonly `firebase_messaging`). Add the Push Notifications capability to your distribution provisioning profile.

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
