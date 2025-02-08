import Flutter
import UIKit

public class RestartAppPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "restart", binaryMessenger: registrar.messenger())
        let instance = RestartAppPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "restartApp" {
            DispatchQueue.main.async {
                if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                    appDelegate.restartFlutterApp()
                    result("ok")
                } else {
                    result(FlutterError(code: "APP_DELEGATE_NOT_FOUND", message: "Could not find AppDelegate", details: nil))
                }
            }
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
}