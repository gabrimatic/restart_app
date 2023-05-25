import Flutter
import UIKit
import UserNotifications

// Define the plugin class
public class RestartAppPlugin: NSObject, FlutterPlugin {
  // This function is called when the plugin is registered with Flutter
  public static func register(with registrar: FlutterPluginRegistrar) {
    // Create a FlutterMethodChannel for communicating with Flutter
    let channel = FlutterMethodChannel(name: "restart", binaryMessenger: registrar.messenger())
    // Create an instance of the plugin
    let instance: RestartAppPlugin = RestartAppPlugin()
    // Set the plugin instance as the delegate for method calls from Flutter
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  // This function handles method calls from Flutter
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // If the method call is "restartApp"
    if call.method == "restartApp" {
      // Request notification permissions
      self.requestNotificationPermissions { granted in
        // If permissions are granted, send the notification
        if granted {
          self.sendNotification()
        }
        // Exit the app
        exit(0)
      }
    }
  }

  // This function requests notification permissions
  private func requestNotificationPermissions(completion: @escaping (Bool) -> Void) {
    // Get the current notification center
    let current = UNUserNotificationCenter.current()
    // Request alert notification permissions
    current.requestAuthorization(options: [.alert]) { granted, error in
      // If there's an error, print it and call the completion handler with false
      if let error = error {
        print("Error requesting notification permissions: \(error)")
        completion(false)
      } else {
        // Otherwise, call the completion handler with the granted value
        completion(granted)
      }
    }
  }

  // This function sends a notification
  private func sendNotification() {
    // Set up the notification content
    let content = UNMutableNotificationContent()
    content.title = "Tap to open the app!"
    // Ensure no sound will be played for this notification
    content.sound = nil

    // Set up the notification trigger
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    // Create the notification request
    let request = UNNotificationRequest(identifier: "RestartApp", content: content, trigger: trigger)

    // Add the notification request to the notification center
    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
  }
}
