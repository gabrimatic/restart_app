# restart_app

[![pub package](https://img.shields.io/pub/v/restart_app.svg)](https://pub.dev/packages/restart_app) [![likes](https://img.shields.io/pub/likes/restart_app)](https://pub.dev/packages/restart_app/score) [![pub points](https://img.shields.io/pub/points/restart_app)](https://pub.dev/packages/restart_app/score)

Restart your Flutter app from Dart on Android, iOS, web, macOS, Linux, and Windows.

[Documentation](https://gabrimatic.github.io/restart_app/) · [API reference](https://gabrimatic.github.io/restart_app/reference/api/) · [Example](https://github.com/gabrimatic/restart_app/tree/master/example)

## Quick start

Requires **Flutter 3.22+** and **Dart 3.4+**. Add the dependency:

```yaml
dependencies:
  restart_app: ^1.10.0
```

On iOS, complete the [host setup](#ios-setup) before your first restart. Save any state you need to keep and await pending writes, then call from an async action on the main isolate:

```dart
import 'package:restart_app/restart_app.dart';

final result = await Restart.restartApp();

if (!result.success) {
  // Handle result.code and result.message.
}
```

`RestartResult` reports whether the restart request was accepted, the resolved `mode`, and any error details. The running Dart code may stop before the future completes.

## Platform behavior

The default mode uses the restart mechanism available on each platform:

| Platform | Default behavior |
|----------|------------------|
| Android | Relaunches the main activity. Use `RestartMode.process` for a new process. Android TV and Fire TV launcher entries are supported. |
| iOS | Creates a new Flutter engine and widget tree in the same process. Requires [host setup](#ios-setup); native global and singleton state remain alive. |
| Web | Reloads the current page, preserving its URL and route. |
| macOS | Launches a new app instance and requests termination of the current one. |
| Linux | Replaces the current process image with the app executable. The PID can remain unchanged. |
| Windows | Launches a new process and terminates the current one. |

See the [platform guide](https://gabrimatic.github.io/restart_app/product/platform-behavior/) for supported modes, lifecycle requirements, and packaging limits.

## iOS setup

The app must register its plugins on each replacement Flutter engine.

In `ios/Runner/AppDelegate.swift`, add `import restart_app`. Inside your existing `application(_:didFinishLaunchingWithOptions:)`, add this callback before the call to `super.application`:

```swift
RestartAppPlugin.configureEngineRestart { engine in
  GeneratedPluginRegistrant.register(with: engine)
}
```

Keep your existing initial plugin registration. UIScene apps register their initial engine in `didInitializeImplicitFlutterEngine`; classic apps register it in `application(_:didFinishLaunchingWithOptions:)`.

The [iOS guide](https://gabrimatic.github.io/restart_app/product/ios-engine-restart/) includes complete examples for both lifecycles, scene migration, and custom windows. Apps built with Xcode 27 require the UIScene lifecycle. Request an engine restart while the app is active.

Without this setup, the default restart returns a failed result. iOS does not support automatic full process restart. The optional `RestartMode.notificationFallback` exits the app and requires notification permission and a user tap to reopen it.

## Configuration

Use `RestartMode.platformDefault` for the behavior above, or select a supported `mode` explicitly. Other options control web destinations, Android process termination, and iOS fallback notification text.

- [Configuration](https://gabrimatic.github.io/restart_app/reference/configuration/): options and defaults.
- [API reference](https://gabrimatic.github.io/restart_app/reference/api/): results, capabilities, errors, and web URL behavior.
- [Linux arguments](https://gabrimatic.github.io/restart_app/reference/linux/): preserve command-line arguments across restarts.
- [Background isolates](https://gabrimatic.github.io/restart_app/product/background-isolates/): coordinate worker requests and saved state through the main isolate.

## Requirements

The plugin's native minimums are Android 21, iOS 12, and macOS 10.15. Android builds require Java 17 and Android Gradle Plugin 8 or 9.

Your Flutter SDK and other dependencies can require newer operating systems and build tools. See the [requirements guide](https://gabrimatic.github.io/restart_app/quickstart/#requirements) for SDK compatibility and Android build configuration.

## Agent skills

The package includes optional skills for restart integration and iOS engine setup. With Dart 3.12 or later, run from your Flutter project:

```sh
flutter pub get
dart run skills@ get restart_app
```

Select the skills when prompted, or append `--all` to install both. Run the command again after upgrading the package. See the [agent skills guide](https://gabrimatic.github.io/restart_app/agent-skills/) for requirements and installation details.

## Author

Created by [Soroush Yousefpour](https://gabrimatic.info)

<a href="https://www.buymeacoffee.com/gabrimatic"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy me a coffee" width="170" height="37"></a>
