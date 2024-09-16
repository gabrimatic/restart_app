import Flutter
import UIKit

/// `RestartAppPlugin` is a Flutter plugin that provides functionality to restart
/// the iOS app by reinitializing the Flutter engine and resetting the root view controller.
public class RestartAppPlugin: NSObject, FlutterPlugin {
    /// Holds a reference to the plugin registrar
    var registrar: FlutterPluginRegistrar?

    /// Registers this plugin with the Flutter engine.
    ///
    /// - Parameter registrar: The plugin registrar for registering plugins.
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "restart", binaryMessenger: registrar.messenger())
        let instance = RestartAppPlugin()
        instance.registrar = registrar
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    /// Handles method calls from Flutter.
    ///
    /// - Parameters:
    ///   - call: The method call received from Flutter.
    ///   - result: A callback to send the result back to Flutter.
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "restartApp" {
            restartApp()
            result("ok")
        } else {
            result(FlutterMethodNotImplemented)
        }
    }

    /// Restarts the app by reinitializing the Flutter engine and resetting the root view controller.
    ///
    /// This method performs the following steps:
    /// 1. Finds the application's main window
    /// 2. Removes the current root view controller
    /// 3. Creates a new Flutter engine
    /// 4. Registers plugins with the new engine using runtime reflection
    /// 5. Creates a new Flutter view controller with the new engine
    /// 6. Sets the new view controller as the root view controller
    ///
    /// Note: This method should be used with caution as it may have implications on app state and plugin functionality.
    private func restartApp() {
        DispatchQueue.main.async {
            // Find the application's main window
            guard let window = UIApplication.shared.windows.first else {
                print("Unable to find the application's window.")
                return
            }

            // Remove current rootViewController
            window.rootViewController = nil

            // Create a new FlutterEngine
            let newEngine = FlutterEngine(name: "io.flutter", project: nil)
            newEngine.run()

            // Register plugins with the new engine using reflection
            // This approach is used to avoid requiring modifications to the user's project
            if let registrarClass = NSClassFromString("GeneratedPluginRegistrant") as? NSObject.Type {
                let selector = NSSelectorFromString("registerWithRegistry:")
                if registrarClass.responds(to: selector) {
                    _ = registrarClass.perform(selector, with: newEngine)
                } else {
                    print("GeneratedPluginRegistrant does not respond to registerWithRegistry:")
                }
            } else {
                print("Unable to find GeneratedPluginRegistrant.")
            }

            // Create a new FlutterViewController with the new engine
            let flutterViewController = FlutterViewController(engine: newEngine, nibName: nil, bundle: nil)

            // Set the new rootViewController
            window.rootViewController = flutterViewController
            window.makeKeyAndVisible()
        }
    }
}