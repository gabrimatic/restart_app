import Flutter
import UIKit
import UserNotifications

public class RestartAppPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "restart", binaryMessenger: registrar.messenger())
    let instance = RestartAppPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    // Remove any stale restart notification from a previous launch that
    // fired after the app was already reopened.
    UNUserNotificationCenter.current()
      .removePendingNotificationRequests(withIdentifiers: ["restart_app"])
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "restartApp" {
      let args = call.arguments as? [String: Any]
      let title = args?["notificationTitle"] as? String ?? "Restart"
      let body = args?["notificationBody"] as? String ?? "Tap to reopen the app."

      UNUserNotificationCenter.current().getNotificationSettings { settings in
        DispatchQueue.main.async {
          switch settings.authorizationStatus {
          case .authorized, .provisional, .ephemeral:
            self.scheduleAndExit(title: title, body: body, result: result)
          case .notDetermined:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
              granted, error in
              DispatchQueue.main.async {
                if let error = error {
                  result(
                    FlutterError(
                      code: "AUTHORIZATION_ERROR",
                      message:
                        "Failed to request notification permission: \(error.localizedDescription)",
                      details: nil
                    ))
                } else if granted {
                  self.scheduleAndExit(title: title, body: body, result: result)
                } else {
                  result(
                    FlutterError(
                      code: "NOTIFICATION_DENIED",
                      message:
                        "Notification permission is required to restart the app on iOS. The user must grant notification permission before calling restartApp().",
                      details: nil
                    ))
                }
              }
            }
          default:
            result(
              FlutterError(
                code: "NOTIFICATION_DENIED",
                message:
                  "Notification permission is required to restart the app on iOS. The user has denied notification permission.",
                details: nil
              ))
          }
        }
      }
    } else {
      result(FlutterMethodNotImplemented)
    }
  }

  private func scheduleAndExit(title: String, body: String, result: @escaping FlutterResult) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(
      identifier: "restart_app", content: content, trigger: trigger)

    UNUserNotificationCenter.current().add(request) { error in
      DispatchQueue.main.async {
        if let error = error {
          result(
            FlutterError(
              code: "NOTIFICATION_FAILED",
              message: "Failed to schedule restart notification: \(error.localizedDescription)",
              details: nil
            ))
        } else {
          result("ok")
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exit(0)
          }
        }
      }
    }
  }
}
