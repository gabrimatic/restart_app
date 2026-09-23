# iOS host setup

Merge the matching setup into the existing delegate. Keep unrelated app setup.

## Flutter 3.41+ UIScene apps

Use this setup when your app has migrated to Flutter's UIScene lifecycle and your delegate already looks like `@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate`.

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

## Classic AppDelegate apps

Use this setup only when your app still registers plugins from `application(_:didFinishLaunchingWithOptions:)`. This legacy lifecycle is for older toolchains. Apps built with Xcode 27 must migrate to UIScene before they can launch.

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

## Custom engines

Use `RestartAppPlugin.setEngineFactory` when the host needs a custom Dart entrypoint, route, or engine configuration. The factory must return a new, running `FlutterEngine` with plugins registered for that engine. If `engine.run()` fails, throw an error instead of returning an unstarted engine. Provide a `windowProvider` and `viewControllerInstaller` for custom scene or native container ownership. Do not reuse the old engine.
