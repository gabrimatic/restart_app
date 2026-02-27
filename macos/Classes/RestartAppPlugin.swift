import Cocoa
import FlutterMacOS

public class RestartAppPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "restart", binaryMessenger: registrar.messenger)
    let instance = RestartAppPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "restartApp" {
      let url = Bundle.main.bundleURL
      let config = NSWorkspace.OpenConfiguration()
      config.createsNewApplicationInstance = true
      // NSApp.terminate(nil) goes through the normal AppKit termination
      // sequence, which may invoke applicationShouldTerminate: on the
      // app delegate. In sandboxed apps this is expected; unsaved-document
      // dialogs from other frameworks could appear but are unlikely in a
      // typical Flutter app.
      NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
        DispatchQueue.main.async {
          if let error = error {
            result(
              FlutterError(
                code: "RESTART_FAILED",
                message: "Failed to launch new application instance: \(error.localizedDescription)",
                details: nil
              ))
          } else {
            result("ok")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
              NSApp.terminate(nil)
            }
          }
        }
      }
    } else {
      result(FlutterMethodNotImplemented)
    }
  }
}
