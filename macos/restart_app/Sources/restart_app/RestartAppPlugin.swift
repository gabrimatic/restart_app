import Cocoa
import FlutterMacOS

public class RestartAppPlugin: NSObject, FlutterPlugin {
  // All access occurs on the main queue. Keep this process-wide because a host
  // can register the plugin with more than one Flutter engine.
  private static var restartPending = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "restart", binaryMessenger: registrar.messenger)
    let instance = RestartAppPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // NSWorkspace and NSApp must be used on the main thread; hop explicitly in
    // case the host app routes platform channels through a custom task runner.
    DispatchQueue.main.async {
      self.handleOnMain(call, result: result)
    }
  }

  private func handleOnMain(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "restartCapability" {
      result([
        "fullProcessRestart": true,
        "flutterEngineRestart": false,
        "notificationFallback": false,
        "engineRestartConfigured": false,
        "platformDefaultMode": "process",
        "reason": NSNull(),
      ])
    } else if call.method == "restartApp" {
      let args = call.arguments as? [String: Any] ?? [:]
      let mode = args["mode"] as? String ?? "platformDefault"
      let structuredResult = args["structuredResult"] as? Bool ?? false

      if mode != "platformDefault" && mode != "process" {
        result(
          FlutterError(
            code: "UNSUPPORTED_RESTART_MODE",
            message: "Restart mode '\(mode)' is not supported on macOS.",
            details: nil
          ))
        return
      }

      guard !RestartAppPlugin.restartPending else {
        result(
          FlutterError(
            code: "RESTART_ALREADY_IN_PROGRESS",
            message: "An application restart is already in progress.",
            details: nil
          ))
        return
      }
      RestartAppPlugin.restartPending = true

      let url = Bundle.main.bundleURL
      let config = NSWorkspace.OpenConfiguration()
      config.createsNewApplicationInstance = true
      // NSApp.terminate(nil) goes through the normal AppKit termination
      // sequence, which may invoke applicationShouldTerminate: on the
      // app delegate. In sandboxed apps this is expected; unsaved-document
      // dialogs from other frameworks could appear but are unlikely in a
      // typical Flutter app.
      NSWorkspace.shared.openApplication(at: url, configuration: config) { application, error in
        DispatchQueue.main.async {
          if let error = error {
            RestartAppPlugin.restartPending = false
            result(
              FlutterError(
                code: "RESTART_FAILED",
                message: "Failed to launch new application instance: \(error.localizedDescription)",
                details: nil
              ))
          } else if application == nil {
            RestartAppPlugin.restartPending = false
            result(
              FlutterError(
                code: "RESTART_FAILED",
                message: "The new application instance did not launch.",
                details: nil
              ))
          } else {
            if structuredResult {
              result([
                "success": true,
                "mode": "process",
              ])
            } else {
              result("ok")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
              // Retain the guard if the host vetoes termination. A replacement
              // already exists, so retrying would create another instance.
              NSApp?.terminate(nil)
            }
          }
        }
      }
    } else {
      result(FlutterMethodNotImplemented)
    }
  }
}
