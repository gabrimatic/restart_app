# iOS host setup

Configure plugin registration in `ios/Runner/AppDelegate.swift` so each replacement engine can use the app's plugins. Merge the matching example into the existing delegate and preserve unrelated initialization.

## UIScene apps

Use this example if your app uses Flutter's UIScene lifecycle, which is the default for new apps since Flutter 3.41. Keep the initial engine's plugin registration in `didInitializeImplicitFlutterEngine`; the `configureEngineRestart` callback registers plugins for each replacement engine.

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

The app must also have Flutter's UIScene configuration in `Info.plist`. For an older host, complete the [Flutter UIScene migration](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate). A custom `SceneDelegate` must extend `FlutterSceneDelegate` or implement `FlutterSceneLifeCycleProvider` so Flutter receives scene callbacks.

## Classic AppDelegate apps

For an older host that registers plugins in `didFinishLaunchingWithOptions`, keep that registration and add the restart callback:

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

This layout is for the older app lifecycle. Apps built with the iOS 27 SDK must migrate to UIScene.

Rebuild the iOS app after changing Swift code. Hot reload does not apply these changes. Once configured, both `RestartMode.platformDefault` and `RestartMode.flutterEngine` recreate the engine in the existing process. Without configuration, they fail with `IOS_ENGINE_RESTART_NOT_CONFIGURED`.

## Custom windows and native containers

Request engine restart while the app is active. The default installer replaces a root `FlutterViewController` in a visible window, selected from foreground-active scenes with preference for the key window.

For a host with several windows, provide `windowProvider` to select the intended one. Returning `nil` produces `IOS_NO_ACTIVE_WINDOW`; it does not select another window. For an embedded Flutter view, provide `viewControllerInstaller` to install the replacement controller in the host's container. Without it, a non-Flutter root controller produces `IOS_UNSAFE_ROOT_REPLACEMENT`.

`beforeRestart` runs before the new engine is created. `afterRestart` receives the new engine after its view controller is installed, before the plugin destroys the old engine's context. Use these hooks when the host needs to release resources or reconnect custom channels. Saved data and native process-wide state remain the host's responsibility.

## Custom engines

Use `RestartAppPlugin.setEngineFactory` for a custom Dart entrypoint, initial route, or engine configuration. The factory must create a new engine, start it, register its plugins, and return it. Throw if `engine.run()` fails. Never reuse the old engine.

Pass the same `windowProvider` and `viewControllerInstaller` options when the host owns window selection or controller installation. Calling either configuration method again replaces the previous configuration, including custom callbacks.
