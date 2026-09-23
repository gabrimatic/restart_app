# restart_app

[![pub package](https://img.shields.io/pub/v/restart_app.svg)](https://pub.dev/packages/restart_app) [![likes](https://img.shields.io/pub/likes/restart_app)](https://pub.dev/packages/restart_app/score) [![pub points](https://img.shields.io/pub/points/restart_app)](https://pub.dev/packages/restart_app/score)

Restart your Flutter app from Dart on Android, iOS, web, macOS, Linux, and Windows.

[Documentation](https://gabrimatic.github.io/restart_app/) · [API reference](https://gabrimatic.github.io/restart_app/reference/api/) · [Example](https://github.com/gabrimatic/restart_app/tree/master/example)

## Features

- App and process restarts on Android and desktop.
- Flutter engine restarts on iOS, with native setup.
- Flutter web app restarts with JavaScript and WebAssembly support.
- Restart results, error details, and platform capability checks.
- Bundled AI agent skills for integration and iOS configuration.

## Quick start

Requires Flutter 3.22 or later and Dart 3.4 or later.

```sh
flutter pub add restart_app
```

Import the package and call it from a button or another app action:

```dart
import 'package:restart_app/restart_app.dart';

await Restart.restartApp();
```

**iOS:** complete the [AppDelegate setup](https://gabrimatic.github.io/restart_app/product/ios-engine-restart/) before using this call.

The method returns a `RestartResult` with success or error details. See [error handling](https://gabrimatic.github.io/restart_app/quickstart/#error-handling) for an example.

## Platforms

`Restart.restartApp()` uses the following default behavior:

| Platform | What happens |
| --- | --- |
| Android | Relaunches the app's main activity. Use `RestartMode.process` to also restart the process. Android TV and Fire TV are supported. |
| iOS | Recreates the Flutter engine and starts the Flutter app again within the existing iOS process. Requires the setup below. |
| Web | Reloads the whole Flutter web app at the same URL. |
| macOS | Opens a new app instance and asks the existing instance to quit. |
| Linux | Runs the app executable again, replacing the existing process without changing its process ID. |
| Windows | Opens a new app process and ends the existing process. |

### iOS setup

Add the plugin registration callback to `ios/Runner/AppDelegate.swift` so the new Flutter engine can use your app's plugins. The [iOS guide](https://gabrimatic.github.io/restart_app/product/ios-engine-restart/) has complete examples for UIScene and older AppDelegate projects.

iOS restarts the Flutter engine, not the entire native process. Native singletons remain in memory. The optional notification fallback closes the app and requires a notification tap to reopen it.

### Web routes

A restart reloads the whole Flutter web app. The browser URL stays the same, so an app opened at `/settings` restarts at `/settings`, where your router decides what to show.

To restart at another route, pass `webOrigin`:

```dart
await Restart.restartApp(webOrigin: '/');
```

Here, `/` is the website root. Apps hosted in a subdirectory should use that path, such as `/my-app/`. Hash routing is also supported with values such as `#/home`. See [web destinations](https://gabrimatic.github.io/restart_app/reference/api/#web-destinations).

## AI agent skills

The package includes two skills that help AI coding agents use the restart API and configure iOS engine restarts. Install them from your Flutter project with Dart 3.12 or later:

```sh
dart run skills@ get restart_app
```

Select the skills when prompted. Run the command again after upgrading the package to update your agent's instructions. See the [agent skills guide](https://gabrimatic.github.io/restart_app/agent-skills/) for other installation options.

## Documentation

- [Requirements](https://gabrimatic.github.io/restart_app/quickstart/#requirements): Flutter, native OS, and build tool versions.
- [Platform behavior](https://gabrimatic.github.io/restart_app/product/platform-behavior/): restart modes and platform limits.
- [Configuration](https://gabrimatic.github.io/restart_app/reference/configuration/): saved data, web routes, and restart options.
- [Background isolates](https://gabrimatic.github.io/restart_app/product/background-isolates/): request a restart from a worker.
- [Linux arguments](https://gabrimatic.github.io/restart_app/reference/linux/): keep command-line arguments after a restart.

## Author

Created by [Soroush Yousefpour](https://gabrimatic.info)

<a href="https://www.buymeacoffee.com/gabrimatic"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy me a coffee" width="170" height="37"></a>
