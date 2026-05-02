import UIKit
import Flutter
import restart_app

@main
@objc class AppDelegate: FlutterAppDelegate {
    var flutterEngine: FlutterEngine?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        RestartAppPlugin.setEngineFactory({ [weak self] in
            let engine = FlutterEngine(name: "restart_app_example_engine")

            guard engine.run() else {
                throw NSError(
                    domain: "restart_app",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to run FlutterEngine"]
                )
            }

            GeneratedPluginRegistrant.register(with: engine)
            self?.flutterEngine = engine
            return engine
        })

        let initialEngine = FlutterEngine(name: "restart_app_example_initial_engine")
        initialEngine.run()
        GeneratedPluginRegistrant.register(with: initialEngine)
        flutterEngine = initialEngine

        let flutterViewController = FlutterViewController(engine: initialEngine, nibName: nil, bundle: nil)
        self.window = UIWindow(frame: UIScreen.main.bounds)
        self.window?.rootViewController = flutterViewController
        self.window?.makeKeyAndVisible()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
