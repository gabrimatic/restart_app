# restart_app

[![pub package](https://img.shields.io/pub/v/restart_app.svg)](https://pub.dev/packages/restart_app) [![likes](https://img.shields.io/pub/likes/restart_app)](https://pub.dev/packages/restart_app/score) [![popularity](https://img.shields.io/pub/popularity/restart_app)](https://pub.dev/packages/restart_app/score) [![pub points](https://img.shields.io/pub/points/restart_app)](https://pub.dev/packages/restart_app/score)

Restart or relaunch your Flutter app from Dart with one call.

Each platform uses the safest supported restart path available to Flutter apps. See the [published docs](https://gabrimatic.github.io/restart_app/) for guides, reference, and deployment details. The [platform behavior guide](https://gabrimatic.github.io/restart_app/product/platform-behavior/) covers the exact native mechanism on each target.

## Quick start

Add the dependency:

```yaml
dependencies:
  restart_app: ^1.9.2
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

## Agent skills

This package includes agent skills for restart integration and iOS engine setup.
Install them from your Flutter project with Dart 3.12 or later after fetching dependencies:

```bash
flutter pub get
dart run skills@ get restart_app
```

Select the skills when prompted, or append `--all` to install both. Run the
command again after upgrading `restart_app` to update the instructions alongside
your resolved package version. The CLI is a development tool, not an app dependency.

See the [agent skills guide](https://gabrimatic.github.io/restart_app/agent-skills/)
for requirements, supported workflows, and installation details.

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
| `webOrigin` | Web | Custom URL for the reload. When null, the current page reloads and keeps its route. Supports hash strategy (e.g. `'#/home'`). |
| `notificationTitle` | iOS | Title of the local notification shown only when `mode` is `notificationFallback`. Defaults to `Restart`. |
| `notificationBody` | iOS | Body of the local notification shown only when `mode` is `notificationFallback`. Defaults to `Tap to reopen the app.` |
| `forceKill` | Android | When `true`, fully terminates the process after launching the new activity. Defaults to `false`. `RestartMode.process` enables this path automatically on Android. |

## Platform behavior

| Platform | Mechanism | Limitations |
|----------|-----------|-------------|
| **Android** | Relaunches the main activity via `PackageManager`. Supports Android TV and Fire TV via leanback launcher fallback. `RestartMode.process` and `forceKill: true` kill the process after launch for a clean cold start. | Requires an attached activity and a launchable app entry point. A default restart does not guarantee a new native process. |
| **iOS** | Recommended: opt-in Flutter engine restart that creates a new `FlutterEngine`, runs Dart again, re-registers plugins, and replaces the root `FlutterViewController` in the same iOS process. Legacy: local notification + `exit(0)` + user tap. | iOS has no public API for automatic full process restart. Engine restart is not a process restart and cannot reset native singleton state. Legacy fallback requires notification permission and user action. |
| **Web** | Reloads the page using `window.location`. | Persist state first. The browser and host routing determine navigation and reload behavior. |
| **macOS** | Launches a new instance via `NSWorkspace` and terminates the current process. | Test the signed distribution you ship, including sandbox and termination delegates. Launch failures return `RESTART_FAILED`; a host termination veto can leave the old instance running. |
| **Linux** | Replaces the current process via `execv`. | The executable must remain accessible. The PID can stay the same because `execv` replaces the process image. Configure argv preservation if needed. |
| **Windows** | Launches a new instance via `CreateProcess` and terminates the current process. | Uses the desktop process-launch path, not package activation APIs. Test MSIX/Store packaging separately; launch restrictions return `RESTART_FAILED`. |

## iOS

iOS does not provide a public API for an app to terminate itself and automatically launch a fresh process of the same app. Android-style full process restart is not available on iOS with public APIs.

`restart_app` supports two iOS behaviors:

1. **Flutter engine restart**, recommended. This keeps the iOS process alive, creates a new `FlutterEngine`, runs the Dart entrypoint again, re-registers plugins through the host app's `GeneratedPluginRegistrant`, creates a new `FlutterViewController`, replaces the active root view controller, and destroys the old engine context.
2. **Notification fallback**, legacy and explicit only. This schedules a local notification, calls `exit(0)`, and requires the user to tap the notification to reopen the app. This is not a true restart and is not recommended as normal product behavior.

### Configure Flutter engine restart

The host app owns `GeneratedPluginRegistrant`, so iOS engine restart requires one app-side setup step.

Choose the snippet that matches your iOS lifecycle.

#### Flutter 3.41+ UIScene apps

Use this shape when your app has migrated to Flutter's UIScene lifecycle and your delegate already looks like `@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate`.

Keep the normal plugin registration for the implicit app engine in `didInitializeImplicitFlutterEngine`. Add `RestartAppPlugin.configureEngineRestart` in `application(_:didFinishLaunchingWithOptions:)` so `restart_app` can register plugins on each newly created engine:

```swift
import UIKit
import Flutter
import restart_app

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    RestartAppPlugin.configureEngineRestart { engine in
      GeneratedPluginRegistrant.register(with: engine)
    }

    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }

  func didInitializeImplicitFlutterEngine(
    _ engineBridge: FlutterImplicitEngineBridge
  ) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
```

This follows Flutter's UIScene migration model: the initial engine is registered through `didInitializeImplicitFlutterEngine`, and restarted engines are registered through the `restart_app` callback above.

`restart_app` prefers the foreground `UIWindowScene` and replaces its key window root `FlutterViewController`. Request restarts while the app is active. If your app has multiple scenes or a custom native shell, pass a `windowProvider` or `viewControllerInstaller` to `configureEngineRestart` so the plugin targets the correct window. A custom `windowProvider` returning `nil` fails with `IOS_NO_ACTIVE_WINDOW`; it does not fall back to another scene. Reconfiguring without a custom installer restores the default root replacement and safety checks.

Complete Flutter's [UIScene migration](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate), including `UIApplicationSceneManifest` in `Info.plist`. Xcode 27 requires the scene lifecycle; the restart callback alone does not migrate the app.

If you implement your own `SceneDelegate`, keep Flutter's scene lifecycle wiring there too: subclass `FlutterSceneDelegate` or conform to `FlutterSceneLifeCycleProvider`, as described in Flutter's [UISceneDelegate migration guide](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate).

#### Classic AppDelegate apps

Use this shape only with older toolchains where your app still registers plugins from `application(_:didFinishLaunchingWithOptions:)`. Apps built with Xcode 27 must migrate to UIScene before they can launch.

In `ios/Runner/AppDelegate.swift`:

```swift
import UIKit
import Flutter
import restart_app

@main
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

These are the plugin's minimum SDK constraints. Your chosen Flutter release,
other dependencies, and distribution channel can require newer operating systems
or build tools. For example, Flutter 3.47 raises its own minimums to Android 24,
iOS 15, and macOS 12. Use an older compatible Flutter SDK for older deployment
targets; the plugin's native Android 21, iOS 12, and macOS 10.15 minimums remain
unchanged. See Flutter's [supported platforms](https://docs.flutter.dev/reference/supported-platforms).

| Platform | Minimum |
|----------|---------|
| Android | `minSdk` 21, Java 17, Android Gradle Plugin 8 or 9 |
| iOS | 12.0 |
| macOS | 10.15 |

The Android module builds on Android Gradle Plugin 8 and 9. It applies the Kotlin Gradle Plugin only when nothing else has already provided Kotlin, so it builds on both AGP majors with the Flutter template default `android.builtInKotlin=false`. Turning built-in Kotlin on is a separate Flutter migration that needs Flutter 3.47 or later; on earlier Flutter releases it fails for every plugin, including Flutter's own plugin template.

## Author

Created by [Soroush Yousefpour](https://gabrimatic.info)

<a href="https://www.buymeacoffee.com/gabrimatic" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Book" style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;-webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;" ></a>
