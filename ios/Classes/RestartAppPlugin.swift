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
            DispatchQueue.main.async {
                let args = call.arguments as? [String: Any] ?? [:]
                let notificationTitle = args["notificationTitle"] as? String ?? "Restarting App"
                let notificationBody = args["notificationBody"] as? String ?? "Please tap here to open the app again."
                let delayBeforeRestart = args["delayBeforeRestart"] as? Int ?? 0
                
                self.restartApp(title: notificationTitle, body: notificationBody, delay: delayBeforeRestart)
                result("ok")
            }
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func restartApp(title: String, body: String, delay: Int) {
        let restartAction = {
            self.requestNotificationPermission { granted in
                if granted {
                    self.scheduleRestartNotification(title: title, body: body)
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    exit(0)
                }
            }
        }
        
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
                restartAction()
            }
        } else {
            restartAction()
        }
    }
    
    private func requestNotificationPermission(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            completion(granted)
        }
    }
    
    private func scheduleRestartNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        // Create custom app icon instead of Flutter icon
        if let bundleId = Bundle.main.bundleIdentifier {
            let urlString = "\(bundleId)://restart"
            if let url = URL(string: urlString) {
                content.userInfo = ["restart_url": urlString]
            }
        }
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "restart_app_notification", content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                print("Error scheduling restart notification: \(error)")
            }
        }
    }
}