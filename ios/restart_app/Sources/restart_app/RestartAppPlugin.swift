import Flutter
import UIKit
import UserNotifications

protocol RestartNotificationService {
  func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void)
  func requestAuthorization(completion: @escaping (Bool, Error?) -> Void)
  func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void)
  func removePendingRestartNotification()
}

private struct SystemRestartNotificationService: RestartNotificationService {
  func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      completion(settings.authorizationStatus)
    }
  }

  func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound], completionHandler: completion)
  }

  func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
    UNUserNotificationCenter.current().add(request, withCompletionHandler: completion)
  }

  func removePendingRestartNotification() {
    UNUserNotificationCenter.current()
      .removePendingNotificationRequests(withIdentifiers: ["restart_app"])
  }
}

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
      return "A restart is already in progress."
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

  struct EngineRestartConfiguration {
    var factory: EngineFactory?
    var windowProvider: WindowProvider?
    var beforeRestart: RestartHook?
    var afterRestart: AfterRestartHook?
    var viewControllerInstaller: ViewControllerInstaller = { window, viewController in
      window.rootViewController = viewController
      window.makeKeyAndVisible()
    }
    var usesCustomViewControllerInstaller = false
  }

  static var engineRestartConfiguration = EngineRestartConfiguration()
  private static var retainedEngine: FlutterEngine?
  private static var restartCounter = 0
  private static var isRestarting = false
  private let notificationService: RestartNotificationService

  public override init() {
    notificationService = SystemRestartNotificationService()
    super.init()
  }

  init(notificationService: RestartNotificationService) {
    self.notificationService = notificationService
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    register(with: registrar, notificationService: SystemRestartNotificationService())
  }

  static func register(
    with registrar: FlutterPluginRegistrar,
    notificationService: RestartNotificationService
  ) {
    let channel = FlutterMethodChannel(name: "restart", binaryMessenger: registrar.messenger())
    let instance = RestartAppPlugin(notificationService: notificationService)
    registrar.addMethodCallDelegate(instance, channel: channel)

    // Another engine can register while the current fallback is scheduling its
    // notification or waiting to exit. Only clean stale requests between restarts.
    if !isRestarting {
      notificationService.removePendingRestartNotification()
    }
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
    var configuration = EngineRestartConfiguration(
      factory: factory,
      windowProvider: windowProvider,
      beforeRestart: beforeRestart,
      afterRestart: afterRestart
    )
    if let viewControllerInstaller = viewControllerInstaller {
      configuration.viewControllerInstaller = viewControllerInstaller
      configuration.usesCustomViewControllerInstaller = true
    }
    engineRestartConfiguration = configuration
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
    guard let mode = IOSRestartMode(rawValue: modeName) else {
      result(
        FlutterError(
          code: "UNSUPPORTED_RESTART_MODE",
          message: "Unsupported restart mode: \(modeName)",
          details: nil
        ))
      return
    }
    let structuredResult = args["structuredResult"] as? Bool ?? false

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
      if Self.engineRestartConfiguration.factory != nil {
        scheduleEngineRestart(result: result, structuredResult: structuredResult)
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

    guard Self.engineRestartConfiguration.factory != nil else {
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

    if !Self.engineRestartConfiguration.usesCustomViewControllerInstaller,
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

    guard let factory = engineRestartConfiguration.factory else {
      NSLog("[restart_app] Engine restart aborted: engine factory missing.")
      return
    }

    guard let window = activeWindow() else {
      NSLog("[restart_app] Engine restart aborted: no active window.")
      return
    }

    if !engineRestartConfiguration.usesCustomViewControllerInstaller,
      !(window.rootViewController is FlutterViewController)
    {
      NSLog("[restart_app] Engine restart aborted: unsafe root replacement.")
      return
    }

    let oldRootViewController = window.rootViewController
    let oldFlutterViewController = findFlutterViewController(in: oldRootViewController)
    let oldEngine = oldFlutterViewController?.engine

    do {
      engineRestartConfiguration.beforeRestart?()
      let newEngine = try factory()
      let newFlutterViewController = FlutterViewController(
        engine: newEngine,
        nibName: nil,
        bundle: nil
      )

      oldRootViewController?.dismiss(animated: false)
      retainedEngine = newEngine
      engineRestartConfiguration.viewControllerInstaller(window, newFlutterViewController)
      engineRestartConfiguration.afterRestart?(newEngine)

      if let oldEngine = oldEngine, oldEngine !== newEngine {
        oldEngine.destroyContext()
      }
    } catch {
      NSLog("[restart_app] Engine restart failed: \(error.localizedDescription)")
    }
  }

  private static func capabilityPayload() -> [String: Any] {
    let configured = engineRestartConfiguration.factory != nil

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
    if let windowProvider = engineRestartConfiguration.windowProvider {
      return windowProvider()
    }

    if #available(iOS 13.0, *) {
      let application = UIApplication.shared
      let scenes = application.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .map { (state: $0.activationState, windows: $0.windows) }
      let usesSceneLifecycle =
        !application.connectedScenes.isEmpty
        || !application.openSessions.isEmpty
        || Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") != nil
      return selectWindow(
        sceneWindows: scenes,
        usesSceneLifecycle: usesSceneLifecycle,
        legacyWindows: { application.windows }
      )
    }

    return UIApplication.shared.windows.first(where: { $0.isKeyWindow })
      ?? UIApplication.shared.windows.first(where: { !$0.isHidden })
  }

  @available(iOS 13.0, *)
  static func selectWindow(
    sceneWindows: [(state: UIScene.ActivationState, windows: [UIWindow])],
    usesSceneLifecycle: Bool,
    legacyWindows: () -> [UIWindow]
  ) -> UIWindow? {
    let activeWindows =
      sceneWindows
      .filter { $0.state == .foregroundActive }
      .flatMap { $0.windows }
    if let window = activeWindows.first(where: { $0.isKeyWindow })
      ?? activeWindows.first(where: { !$0.isHidden && $0.alpha > 0 })
    {
      return window
    }
    // UIApplication.windows can include a background scene's windows. It is a
    // fallback only for hosts that do not use the scene lifecycle at all.
    if usesSceneLifecycle || !sceneWindows.isEmpty {
      return nil
    }
    let windows = legacyWindows()
    return windows.first(where: { $0.isKeyWindow })
      ?? windows.first(where: { !$0.isHidden })
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
    guard !Self.isRestarting else {
      result(IOSRestartError.restartAlreadyInProgress.flutterError)
      return
    }
    // Hold the same process-wide guard while settings, permission, scheduling,
    // and the delayed exit are pending. Each callback returns to the main queue.
    Self.isRestarting = true
    let title = args["notificationTitle"] as? String ?? "Restart"
    let body = args["notificationBody"] as? String ?? "Tap to reopen the app."

    notificationService.authorizationStatus { status in
      DispatchQueue.main.async {
        switch status {
        case .authorized, .provisional, .ephemeral:
          self.scheduleAndExit(
            title: title,
            body: body,
            result: result,
            structuredResult: structuredResult,
            resolvedMode: resolvedMode
          )
        case .notDetermined:
          self.notificationService.requestAuthorization {
            granted, error in
            DispatchQueue.main.async {
              if let error = error {
                Self.isRestarting = false
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
                Self.isRestarting = false
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
          Self.isRestarting = false
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

    notificationService.add(request) { error in
      DispatchQueue.main.async {
        if let error = error {
          Self.isRestarting = false
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
