import Flutter
import UIKit
import UserNotifications

private enum IOSRestartMode: String {
  case platformDefault
  case flutterEngine
  case process
  case notificationFallback
}

private enum IOSRestartError: Error {
  case processRestartUnsupported
  case engineRestartNotConfigured
  case appNotActive
  case noActiveWindow
  case restartAlreadyInProgress
  case unsafeRootReplacement
  case engineRunFailed

  var code: String {
    switch self {
    case .processRestartUnsupported:
      return "IOS_PROCESS_RESTART_UNSUPPORTED"
    case .engineRestartNotConfigured:
      return "IOS_ENGINE_RESTART_NOT_CONFIGURED"
    case .appNotActive:
      return "IOS_APP_NOT_ACTIVE"
    case .noActiveWindow:
      return "IOS_NO_ACTIVE_WINDOW"
    case .restartAlreadyInProgress:
      return "IOS_RESTART_ALREADY_IN_PROGRESS"
    case .unsafeRootReplacement:
      return "IOS_UNSAFE_ROOT_REPLACEMENT"
    case .engineRunFailed:
      return "IOS_ENGINE_RUN_FAILED"
    }
  }

  var message: String {
    switch self {
    case .processRestartUnsupported:
      return "iOS does not provide a public API for automatic full process restart."
    case .engineRestartNotConfigured:
      return "Flutter engine restart is not configured. "
        + "Call RestartAppPlugin.configureEngineRestart(...) in the host app."
    case .appNotActive:
      return "Flutter engine restart can only run while the app is active."
    case .noActiveWindow:
      return "No active UIWindow was found for Flutter engine restart."
    case .restartAlreadyInProgress:
      return "A Flutter engine restart is already in progress."
    case .unsafeRootReplacement:
      return "The active window rootViewController is not a FlutterViewController. "
        + "Provide a custom viewControllerInstaller for add-to-app or custom native shells."
    case .engineRunFailed:
      return "Failed to run the new FlutterEngine."
    }
  }

  var flutterError: FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }
}

public final class RestartAppPlugin: NSObject, FlutterPlugin {
  public typealias EngineFactory = () throws -> FlutterEngine
  public typealias RegisterPlugins = (FlutterEngine) -> Void
  public typealias WindowProvider = () -> UIWindow?
  public typealias RestartHook = () -> Void
  public typealias AfterRestartHook = (FlutterEngine) -> Void
  public typealias ViewControllerInstaller = (UIWindow, FlutterViewController) -> Void

  private static var engineFactory: EngineFactory?
  private static var windowProvider: WindowProvider?
  private static var beforeRestart: RestartHook?
  private static var afterRestart: AfterRestartHook?
  private static var viewControllerInstaller: ViewControllerInstaller = { window, viewController in
    window.rootViewController = viewController
    window.makeKeyAndVisible()
  }
  private static var usesCustomViewControllerInstaller = false
  private static var retainedEngine: FlutterEngine?
  private static var restartCounter = 0
  private static var isRestarting = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "restart", binaryMessenger: registrar.messenger())
    let instance = RestartAppPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    // Remove any stale restart notification from a previous launch that
    // fired after the app was already reopened.
    UNUserNotificationCenter.current()
      .removePendingNotificationRequests(withIdentifiers: ["restart_app"])
  }

  /// Configures the recommended same-process iOS Flutter engine restart.
  ///
  /// The host app owns GeneratedPluginRegistrant, so it must provide plugin
  /// registration for each newly created engine.
  public static func configureEngineRestart(
    registerPlugins: @escaping RegisterPlugins,
    windowProvider: WindowProvider? = nil,
    beforeRestart: RestartHook? = nil,
    afterRestart: AfterRestartHook? = nil,
    viewControllerInstaller: ViewControllerInstaller? = nil
  ) {
    setEngineFactory(
      {
        restartCounter += 1
        let engine = FlutterEngine(name: "restart_app_engine_\(restartCounter)")

        guard engine.run() else {
          throw IOSRestartError.engineRunFailed
        }

        registerPlugins(engine)
        return engine
      },
      windowProvider: windowProvider,
      beforeRestart: beforeRestart,
      afterRestart: afterRestart,
      viewControllerInstaller: viewControllerInstaller
    )
  }

  /// Configures advanced engine restart for custom engines or add-to-app.
  public static func setEngineFactory(
    _ factory: @escaping EngineFactory,
    windowProvider: WindowProvider? = nil,
    beforeRestart: RestartHook? = nil,
    afterRestart: AfterRestartHook? = nil,
    viewControllerInstaller: ViewControllerInstaller? = nil
  ) {
    engineFactory = factory
    self.windowProvider = windowProvider
    self.beforeRestart = beforeRestart
    self.afterRestart = afterRestart

    if let viewControllerInstaller = viewControllerInstaller {
      self.viewControllerInstaller = viewControllerInstaller
      usesCustomViewControllerInstaller = true
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      switch call.method {
      case "restartCapability":
        result(Self.capabilityPayload())
      case "restartApp":
        self.handleRestartApp(call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleRestartApp(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let modeName = args["mode"] as? String ?? IOSRestartMode.platformDefault.rawValue
    let mode = IOSRestartMode(rawValue: modeName) ?? .platformDefault
    let structuredResult = args["structuredResult"] as? Bool ?? false
    let legacyNotificationFallback = args["iosLegacyNotificationFallback"] as? Bool ?? false

    switch mode {
    case .process:
      result(IOSRestartError.processRestartUnsupported.flutterError)
    case .flutterEngine:
      scheduleEngineRestart(result: result, structuredResult: structuredResult)
    case .notificationFallback:
      scheduleNotificationFallback(
        args: args,
        result: result,
        structuredResult: structuredResult,
        resolvedMode: .notificationFallback
      )
    case .platformDefault:
      if Self.engineFactory != nil {
        scheduleEngineRestart(result: result, structuredResult: structuredResult)
      } else if legacyNotificationFallback {
        scheduleNotificationFallback(
          args: args,
          result: result,
          structuredResult: structuredResult,
          resolvedMode: .notificationFallback
        )
      } else {
        result(IOSRestartError.engineRestartNotConfigured.flutterError)
      }
    }
  }

  private func scheduleEngineRestart(result: @escaping FlutterResult, structuredResult: Bool) {
    if Self.isRestarting {
      result(IOSRestartError.restartAlreadyInProgress.flutterError)
      return
    }

    guard Self.engineFactory != nil else {
      result(IOSRestartError.engineRestartNotConfigured.flutterError)
      return
    }

    guard UIApplication.shared.applicationState == .active else {
      result(IOSRestartError.appNotActive.flutterError)
      return
    }

    guard let window = Self.activeWindow() else {
      result(IOSRestartError.noActiveWindow.flutterError)
      return
    }

    if !Self.usesCustomViewControllerInstaller,
      !(window.rootViewController is FlutterViewController)
    {
      result(IOSRestartError.unsafeRootReplacement.flutterError)
      return
    }

    Self.isRestarting = true
    sendOk(result: result, structuredResult: structuredResult, resolvedMode: .flutterEngine)

    // Let the platform channel result cross the old engine before replacing it.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      Self.performEngineRestart()
    }
  }

  private static func performEngineRestart() {
    defer {
      isRestarting = false
    }

    guard UIApplication.shared.applicationState == .active else {
      NSLog("[restart_app] Engine restart aborted: app is not active.")
      return
    }

    guard let factory = engineFactory else {
      NSLog("[restart_app] Engine restart aborted: engine factory missing.")
      return
    }

    guard let window = activeWindow() else {
      NSLog("[restart_app] Engine restart aborted: no active window.")
      return
    }

    if !usesCustomViewControllerInstaller,
      !(window.rootViewController is FlutterViewController)
    {
      NSLog("[restart_app] Engine restart aborted: unsafe root replacement.")
      return
    }

    let oldRootViewController = window.rootViewController
    let oldFlutterViewController = findFlutterViewController(in: oldRootViewController)
    let oldEngine = oldFlutterViewController?.engine

    do {
      let newEngine = try factory()
      let newFlutterViewController = FlutterViewController(
        engine: newEngine,
        nibName: nil,
        bundle: nil
      )

      beforeRestart?()
      oldRootViewController?.dismiss(animated: false)
      retainedEngine = newEngine
      viewControllerInstaller(window, newFlutterViewController)
      afterRestart?(newEngine)

      if let oldEngine = oldEngine, oldEngine !== newEngine {
        oldEngine.destroyContext()
      }
    } catch {
      NSLog("[restart_app] Engine restart failed: \(error.localizedDescription)")
    }
  }

  private static func capabilityPayload() -> [String: Any] {
    let configured = engineFactory != nil

    return [
      "fullProcessRestart": false,
      "flutterEngineRestart": configured,
      "notificationFallback": true,
      "engineRestartConfigured": configured,
      "platformDefaultMode": configured
        ? IOSRestartMode.flutterEngine.rawValue
        : IOSRestartMode.platformDefault.rawValue,
      "reason": configured
        ? NSNull()
        : "iOS full process restart is unsupported. "
          + "Configure Flutter engine restart in the host app.",
    ]
  }

  private static func activeWindow() -> UIWindow? {
    if let window = windowProvider?() {
      return window
    }

    if #available(iOS 13.0, *) {
      let scenes = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .sorted {
          activationRank($0.activationState) > activationRank($1.activationState)
        }

      for scene in scenes {
        if let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) {
          return keyWindow
        }

        if let visibleWindow = scene.windows.first(where: { !$0.isHidden && $0.alpha > 0 }) {
          return visibleWindow
        }
      }
    }

    return UIApplication.shared.windows.first(where: { $0.isKeyWindow })
      ?? UIApplication.shared.windows.first(where: { !$0.isHidden })
  }

  @available(iOS 13.0, *)
  private static func activationRank(_ state: UIScene.ActivationState) -> Int {
    switch state {
    case .foregroundActive:
      return 4
    case .foregroundInactive:
      return 3
    case .background:
      return 2
    case .unattached:
      return 1
    @unknown default:
      return 0
    }
  }

  private static func findFlutterViewController(
    in viewController: UIViewController?
  ) -> FlutterViewController? {
    guard let viewController = viewController else {
      return nil
    }

    if let flutterViewController = viewController as? FlutterViewController {
      return flutterViewController
    }

    if let navigationController = viewController as? UINavigationController {
      return findFlutterViewController(in: navigationController.visibleViewController)
        ?? findFlutterViewController(in: navigationController.topViewController)
    }

    if let tabController = viewController as? UITabBarController {
      return findFlutterViewController(in: tabController.selectedViewController)
    }

    if let presented = viewController.presentedViewController,
      let flutterViewController = findFlutterViewController(in: presented)
    {
      return flutterViewController
    }

    for child in viewController.children {
      if let flutterViewController = findFlutterViewController(in: child) {
        return flutterViewController
      }
    }

    return nil
  }

  private func sendOk(
    result: @escaping FlutterResult,
    structuredResult: Bool,
    resolvedMode: IOSRestartMode
  ) {
    if structuredResult {
      result([
        "success": true,
        "mode": resolvedMode.rawValue,
      ])
    } else {
      result("ok")
    }
  }

  private func scheduleNotificationFallback(
    args: [String: Any],
    result: @escaping FlutterResult,
    structuredResult: Bool,
    resolvedMode: IOSRestartMode
  ) {
    let title = args["notificationTitle"] as? String ?? "Restart"
    let body = args["notificationBody"] as? String ?? "Tap to reopen the app."

    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
          self.scheduleAndExit(
            title: title,
            body: body,
            result: result,
            structuredResult: structuredResult,
            resolvedMode: resolvedMode
          )
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
                self.scheduleAndExit(
                  title: title,
                  body: body,
                  result: result,
                  structuredResult: structuredResult,
                  resolvedMode: resolvedMode
                )
              } else {
                result(
                  FlutterError(
                    code: "NOTIFICATION_DENIED",
                    message:
                      "Notification permission is required for the iOS notification fallback.",
                    details: nil
                  ))
              }
            }
          }
        default:
          result(
            FlutterError(
              code: "NOTIFICATION_DENIED",
              message: "Notification permission is denied for the iOS notification fallback.",
              details: nil
            ))
        }
      }
    }
  }

  private func scheduleAndExit(
    title: String,
    body: String,
    result: @escaping FlutterResult,
    structuredResult: Bool,
    resolvedMode: IOSRestartMode
  ) {
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
          self.sendOk(
            result: result,
            structuredResult: structuredResult,
            resolvedMode: resolvedMode
          )

          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exit(0)
          }
        }
      }
    }
  }
}
