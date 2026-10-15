# restart_app

[![pub package](https://img.shields.io/pub/v/restart_app.svg)](https://pub.dev/packages/restart_app) [![likes](https://img.shields.io/pub/likes/restart_app)](https://pub.dev/packages/restart_app/score) [![pub points](https://img.shields.io/pub/points/restart_app)](https://pub.dev/packages/restart_app/score)

Restart your Flutter app from Dart on Android, iOS, web, macOS, Linux, and Windows.

[Documentation](https://gabrimatic.github.io/restart_app/) · [API reference](https://gabrimatic.github.io/restart_app/reference/api/) · [Example](https://github.com/gabrimatic/restart_app/tree/master/example)

## Features

- A single API for restarting apps across mobile, web, and desktop.
- Configurable restart options, capability checks, and error handling.
- AI agent skills using the [official Dart and Flutter package skills workflow](https://dart.dev/blog/skills-cli-1-0-bundle-and-distribute-ai-agent-skills-for-your-packages).

## Quick start

Add the package to your project:

```sh
flutter pub add restart_app
```

Import the package and restart your app from anywhere:

```dart
import 'package:restart_app/restart_app.dart';

await Restart.restartApp();
```

## iOS setup

In `ios/Runner/AppDelegate.swift`, add the import:

```swift
import restart_app
```

Add this callback at the beginning of your existing `didFinishLaunchingWithOptions` method:

```swift
RestartAppPlugin.configureEngineRestart { engine in
  GeneratedPluginRegistrant.register(with: engine)
}
```

Keep your existing AppDelegate code, including its plugin registration, then rebuild the iOS app.

The [iOS guide](https://gabrimatic.github.io/restart_app/product/ios-engine-restart/) includes complete examples for UIScene and older AppDelegate projects, plus custom setup options.

## Web setup

By default, restarting reloads the entire web app at the same URL. For example, an app opened at `/settings` restarts at `/settings`. Your router determines which screen appears.

To restart at the website root, set `webOrigin` to `/`:

```dart
await Restart.restartApp(webOrigin: '/');
```

For an app hosted in a subdirectory, use its base path, such as `/my-app/`. Hash routes such as `#/home` are also supported.

## Supported platforms

`Restart.restartApp()` uses the default restart behavior for each platform:

| Platform | Restart behavior |
| --- | --- |
| Android | Relaunches the app's main activity. Use `RestartMode.process` to also restart the native process. Android TV and Fire TV are supported. |
| iOS | Starts the Dart app again with a new Flutter engine. The native iOS process stays running. |
| Web | Reloads the whole app at the same browser URL. Supports JavaScript and WebAssembly builds. |
| macOS | Opens a new app instance, then asks the existing instance to quit. |
| Linux | Runs the app executable again, replacing the running program while keeping the same process ID. |
| Windows | Opens a new app process with the original command line, then ends the existing process. |

Restarting does not erase saved preferences, files, or databases.

## Error handling

`Restart.restartApp()` returns a `RestartResult`. If the request fails, `code` and `message` describe the error:

```dart
final result = await Restart.restartApp();

if (!result.success) {
  print('Restart failed: ${result.code}: ${result.message}');
}
```

A successful result means the platform accepted the restart request. Code after the call may not run.

## Requirements

| Component | Minimum |
| --- | --- |
| Dart | 3.4 |
| Flutter | 3.22 |
| Android | API 21, Java 17, Android Gradle Plugin 8.1.4, Kotlin 2.0.21 |
| iOS | 12.0 |
| macOS | 10.15 |

These are the package's minimum requirements. Your Flutter SDK and other dependencies may require newer operating systems or build tools.

## AI agent skills

`restart_app` includes AI agent skills for using the restart API and configuring iOS. They follow the official package skills workflow for Dart and Flutter, using the `skills` CLI maintained and recommended by the Dart team.

After adding the package, run this command from your project directory with Dart 3.12 or later:

```sh
dart run skills@ get -p restart_app
```

Select the skills when prompted. Your coding agent can then use the instructions and examples included with your installed version of the package. Run the command again after upgrading to update the skills.

## Documentation

- [Requirements](https://gabrimatic.github.io/restart_app/quickstart/#requirements): SDK, operating system, and build tool compatibility.
- [Configuration](https://gabrimatic.github.io/restart_app/reference/configuration/): restart modes, web destinations, and saved data.
- [Platform behavior](https://gabrimatic.github.io/restart_app/product/platform-behavior/): available modes and platform limitations.
- [Background isolates](https://gabrimatic.github.io/restart_app/product/background-isolates/): send a restart request from a worker to the main isolate.
- [Linux arguments](https://gabrimatic.github.io/restart_app/reference/linux/): preserve command-line arguments when restarting.
- [Agent skills](https://gabrimatic.github.io/restart_app/agent-skills/): installation options and updates.
- [API reference](https://gabrimatic.github.io/restart_app/reference/api/): parameters, results, and capability checks.

## Author

Created by [Soroush Yousefpour](https://gabrimatic.info)

<a href="https://www.buymeacoffee.com/gabrimatic"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy me a coffee" width="170" height="37"></a>
