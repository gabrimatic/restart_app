import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    var flutterEngine: FlutterEngine?

    func restartFlutterApp() {
        // Remove the current FlutterViewController
        if let window = self.window {
            window.rootViewController = nil
        }

        // Create a new FlutterEngine
        flutterEngine = FlutterEngine(name: "io.flutter")
        flutterEngine?.run()

        // Re-register plugins with the new engine
        GeneratedPluginRegistrant.register(with: flutterEngine!)

        // Create a new FlutterViewController with the new engine
        let flutterViewController = FlutterViewController(engine: flutterEngine!, nibName: nil, bundle: nil)

        // Set the new FlutterViewController as rootViewController
        if let window = self.window {
            window.rootViewController = flutterViewController
            window.makeKeyAndVisible()
        }
    }

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        flutterEngine = FlutterEngine(name: "io.flutter")
        flutterEngine?.run()
        GeneratedPluginRegistrant.register(with: self.flutterEngine!)
        let flutterViewController = FlutterViewController(engine: flutterEngine!, nibName: nil, bundle: nil)
        self.window = UIWindow(frame: UIScreen.main.bounds)
        self.window?.rootViewController = flutterViewController
        self.window?.makeKeyAndVisible()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}