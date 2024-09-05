import Flutter
import UIKit
import UserNotifications

/// `RestartAppPlugin` is a Flutter plugin that provides functionality to restart
/// the iOS app by scheduling a notification and then terminating the app.
/// This implementation is specific to the iOS platform.
public class RestartAppPlugin: NSObject, FlutterPlugin {
    /// The Flutter method channel used for communication between Dart and native code.
    static var channel: FlutterMethodChannel?
    
    /// Registers this plugin with the Flutter engine.
    ///
    /// - Parameter registrar: The plugin registrar for registering plugins.
    public static func register(with registrar: FlutterPluginRegistrar) {
        channel = FlutterMethodChannel(name: "restart", binaryMessenger: registrar.messenger())
        let instance = RestartAppPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel!)
    }
    
    /// Handles method calls from Flutter.
    ///
    /// - Parameters:
    ///   - call: The method call received from Flutter.
    ///   - result: A callback to send the result back to Flutter.
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "restartApp" {
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
                return
            }
            
            let notificationTitle = args["notificationTitle"] as? String ?? "App Restart"
            let notificationBody = args["notificationBody"] as? String ?? "Tap to reopen the app"
            
            requestNotificationPermissions { granted in
                if granted {
                    self.scheduleNotification(title: notificationTitle, body: notificationBody) { success in
                        if success {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                exit(0)
                            }
                        } else {
                            result(FlutterError(code: "NOTIFICATION_FAILED", message: "Failed to schedule notification", details: nil))
                        }
                    }
                } else {
                    result(FlutterError(code: "PERMISSION_DENIED", message: "Notification permission not granted", details: nil))
                }
            }
            result("Scheduling restart notification...")
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
    
    /// Requests notification permissions from the user.
    ///
    /// - Parameter completion: A closure that is called with a boolean indicating
    ///   whether notification permissions were granted.
    private func requestNotificationPermissions(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    /// Schedules a local notification to appear after the app is terminated.
    /// This method is specific to iOS and should not be called on other platforms.
    ///
    /// - Parameters:
    ///   - title: The title to display in the notification.
    ///   - body: The body message to display in the notification.
    ///   - completion: A closure that is called with a boolean indicating
    ///     whether the notification was successfully scheduled.
    private func scheduleNotification(title: String, body: String, completion: @escaping (Bool) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        
        // Add a custom action to relaunch the app
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            content.userInfo = ["bundleIdentifier": bundleIdentifier]
            content.categoryIdentifier = "RESTART_CATEGORY"
        }
        
        // Schedule the notification to appear 2 seconds from now
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: "RestartApp", content: content, trigger: trigger)
        
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.add(request) { error in
            completion(error == nil)
        }
    }
}