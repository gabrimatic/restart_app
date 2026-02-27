import Flutter
import UIKit
import UserNotifications

public class RestartAppPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "restart", binaryMessenger: registrar.messenger())
        let instance = RestartAppPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
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
                        self.scheduleNotification(title: title, body: body)
                        result("ok")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            exit(0)
                        }
                    case .notDetermined:
                        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                            DispatchQueue.main.async {
                                if granted {
                                    self.scheduleNotification(title: title, body: body)
                                    result("ok")
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        exit(0)
                                    }
                                } else {
                                    result(FlutterError(
                                        code: "NOTIFICATION_DENIED",
                                        message: "Notification permission is required to restart the app on iOS. The user must grant notification permission before calling restartApp().",
                                        details: nil
                                    ))
                                }
                            }
                        }
                    default:
                        result(FlutterError(
                            code: "NOTIFICATION_DENIED",
                            message: "Notification permission is required to restart the app on iOS. The user has denied notification permission.",
                            details: nil
                        ))
                    }
                }
            }
        } else {
            result(FlutterMethodNotImplemented)
        }
    }

    private func scheduleNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "restart_app", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[restart_app] Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }
}
