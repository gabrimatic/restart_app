import Flutter
import UIKit
import UserNotifications
import XCTest

@testable import restart_app

@MainActor
class RunnerTests: XCTestCase {
  private enum TestError: Error { case factoryMustNotRun }
  private var savedConfiguration: RestartAppPlugin.EngineRestartConfiguration?

  override func setUp() {
    super.setUp()
    savedConfiguration = RestartAppPlugin.engineRestartConfiguration
  }

  override func tearDown() {
    if let savedConfiguration = savedConfiguration {
      RestartAppPlugin.engineRestartConfiguration = savedConfiguration
    }
    super.tearDown()
  }

  func testAutomaticWindowSelectionRejectsInactiveScenes() {
    let window = SelectionWindow()
    window.reportsKeyWindow = true
    for state in [UIScene.ActivationState.foregroundInactive, .background, .unattached] {
      XCTAssertNil(
        RestartAppPlugin.selectWindow(
          sceneWindows: [(state: state, windows: [window])],
          usesSceneLifecycle: true,
          legacyWindows: { [window] }
        ), "A scene in state \(state.rawValue) must not be restarted"
      )
    }
  }

  func testAutomaticWindowSelectionPrefersAnActiveKeyWindow() {
    let inactiveKeyWindow = SelectionWindow()
    inactiveKeyWindow.reportsKeyWindow = true
    let visibleWindow = SelectionWindow()
    visibleWindow.isHidden = false
    let activeKeyWindow = SelectionWindow()
    activeKeyWindow.reportsKeyWindow = true
    let selected = RestartAppPlugin.selectWindow(
      sceneWindows: [
        (state: .background, windows: [inactiveKeyWindow]),
        (state: .foregroundActive, windows: [visibleWindow]),
        (state: .foregroundActive, windows: [activeKeyWindow]),
      ],
      usesSceneLifecycle: true,
      legacyWindows: { [inactiveKeyWindow] }
    )
    XCTAssertTrue(selected === activeKeyWindow)
  }

  func testAutomaticWindowSelectionUsesOnlyVisibleActiveWindows() {
    let hiddenWindow = SelectionWindow()
    hiddenWindow.isHidden = true
    let transparentWindow = SelectionWindow()
    transparentWindow.isHidden = false
    transparentWindow.alpha = 0
    let visibleWindow = SelectionWindow()
    visibleWindow.isHidden = false
    XCTAssertTrue(
      RestartAppPlugin.selectWindow(
        sceneWindows: [
          (state: .foregroundActive, windows: [hiddenWindow, transparentWindow, visibleWindow])
        ],
        usesSceneLifecycle: true,
        legacyWindows: { [] }
      ) === visibleWindow
    )
  }

  func testSceneLifecycleWithoutAnActiveWindowDoesNotUseLegacyWindows() {
    let legacyWindow = SelectionWindow()
    legacyWindow.reportsKeyWindow = true
    var readLegacyWindows = false
    XCTAssertNil(
      RestartAppPlugin.selectWindow(
        sceneWindows: [],
        usesSceneLifecycle: true,
        legacyWindows: {
          readLegacyWindows = true
          return [legacyWindow]
        }
      )
    )
    XCTAssertFalse(readLegacyWindows)
  }

  func testLegacyHostWithoutScenesStillSelectsItsWindow() {
    let legacyWindow = SelectionWindow()
    legacyWindow.reportsKeyWindow = true
    XCTAssertTrue(
      RestartAppPlugin.selectWindow(
        sceneWindows: [], usesSceneLifecycle: false, legacyWindows: { [legacyWindow] }
      ) === legacyWindow
    )
  }

  func testNotificationFallbackCannotRaceAPendingEngineRestart() {
    let window = UIWindow()
    let factoryCalled = expectation(description: "engine factory called")
    RestartAppPlugin.setEngineFactory(
      {
        factoryCalled.fulfill()
        throw TestError.factoryMustNotRun
      },
      windowProvider: { window },
      viewControllerInstaller: { _, _ in XCTFail("A failed factory must not install a controller") }
    )
    let notifications = NotificationService()
    let accepted = expectation(description: "engine restart accepted")
    let rejected = expectation(description: "notification restart rejected")
    RestartAppPlugin().handle(restartCall("flutterEngine")) { value in
      XCTAssertEqual(value as? String, "ok")
      accepted.fulfill()
      RestartAppPlugin(notificationService: notifications).handle(
        self.restartCall("notificationFallback")
      ) { value in
        XCTAssertEqual((value as? FlutterError)?.code, "IOS_RESTART_ALREADY_IN_PROGRESS")
        rejected.fulfill()
      }
    }
    wait(for: [accepted, rejected, factoryCalled], timeout: 2)
    XCTAssertEqual(notifications.statusRequests, 0)
  }

  func testPendingNotificationSettingsRejectBothRestartModesAndRecoverAfterDenial() {
    RestartAppPlugin.setEngineFactory(
      { throw TestError.factoryMustNotRun }, windowProvider: { nil }
    )
    let notifications = NotificationService()
    notifications.status = nil
    let requested = expectation(description: "settings requested")
    notifications.onStatusRequest = { requested.fulfill() }
    let denied = expectation(description: "notification denied")
    RestartAppPlugin(notificationService: notifications).handle(restartCall("notificationFallback"))
    {
      value in
      XCTAssertEqual((value as? FlutterError)?.code, "NOTIFICATION_DENIED")
      denied.fulfill()
    }
    wait(for: [requested], timeout: 2)

    assertRestartError("IOS_RESTART_ALREADY_IN_PROGRESS", mode: "flutterEngine")
    assertRestartError("IOS_RESTART_ALREADY_IN_PROGRESS", mode: "notificationFallback")
    notifications.statusCompletion?(.denied)
    wait(for: [denied], timeout: 2)
    assertRestartError("IOS_NO_ACTIVE_WINDOW", mode: "flutterEngine")
  }

  func testPendingNotificationPermissionRejectsEngineRestartAndRecoversAfterDenial() {
    RestartAppPlugin.setEngineFactory(
      { throw TestError.factoryMustNotRun }, windowProvider: { nil }
    )
    let notifications = NotificationService()
    notifications.status = .notDetermined
    notifications.authorizationResponse = nil
    let requested = expectation(description: "permission requested")
    notifications.onAuthorizationRequest = { requested.fulfill() }
    let denied = expectation(description: "permission denied")
    RestartAppPlugin(notificationService: notifications).handle(restartCall("notificationFallback"))
    {
      value in
      XCTAssertEqual((value as? FlutterError)?.code, "NOTIFICATION_DENIED")
      denied.fulfill()
    }
    wait(for: [requested], timeout: 2)
    assertRestartError("IOS_RESTART_ALREADY_IN_PROGRESS", mode: "flutterEngine")
    notifications.authorizationCompletion?(false, nil)
    wait(for: [denied], timeout: 2)
    assertRestartError("IOS_NO_ACTIVE_WINDOW", mode: "flutterEngine")
  }

  func testNotificationAuthorizationErrorReleasesRestartGuard() {
    RestartAppPlugin.setEngineFactory(
      { throw TestError.factoryMustNotRun }, windowProvider: { nil }
    )
    let notifications = NotificationService()
    notifications.status = .notDetermined
    notifications.authorizationResponse = (false, TestError.factoryMustNotRun)
    assertRestartError(
      "AUTHORIZATION_ERROR", mode: "notificationFallback", notifications: notifications)
    assertRestartError("IOS_NO_ACTIVE_WINDOW", mode: "flutterEngine")
  }

  func testNotificationScheduleFailureReleasesRestartGuard() {
    RestartAppPlugin.setEngineFactory(
      { throw TestError.factoryMustNotRun }, windowProvider: { nil }
    )
    let notifications = NotificationService()
    notifications.status = .authorized
    notifications.holdScheduleCompletion = true
    let requested = expectation(description: "notification scheduled")
    notifications.onScheduleRequest = { requested.fulfill() }
    let failed = expectation(description: "notification scheduling failed")
    RestartAppPlugin(notificationService: notifications).handle(restartCall("notificationFallback"))
    {
      value in
      XCTAssertEqual((value as? FlutterError)?.code, "NOTIFICATION_FAILED")
      failed.fulfill()
    }
    wait(for: [requested], timeout: 2)
    assertRestartError("IOS_RESTART_ALREADY_IN_PROGRESS", mode: "notificationFallback")
    notifications.scheduleCompletion?(TestError.factoryMustNotRun)
    wait(for: [failed], timeout: 2)
    assertRestartError("IOS_NO_ACTIVE_WINDOW", mode: "flutterEngine")
  }

  func testAnotherEngineRegistrationPreservesAnInFlightRestartNotification() throws {
    let notifications = NotificationService()
    notifications.status = .authorized
    notifications.holdScheduleCompletion = true
    let scheduled = expectation(description: "restart notification scheduling pending")
    notifications.onScheduleRequest = { scheduled.fulfill() }
    let failed = expectation(description: "notification failure released guard")
    RestartAppPlugin(notificationService: notifications).handle(restartCall("notificationFallback"))
    {
      value in
      XCTAssertEqual((value as? FlutterError)?.code, "NOTIFICATION_FAILED")
      failed.fulfill()
    }
    wait(for: [scheduled], timeout: 2)

    let engine = FlutterEngine(name: "restart_app_registration_test")
    XCTAssertTrue(engine.run())
    defer { engine.destroyContext() }
    let registrar = try XCTUnwrap(engine.registrar(forPlugin: "RestartAppPlugin"))
    RestartAppPlugin.register(with: registrar, notificationService: notifications)
    XCTAssertEqual(notifications.pendingIdentifiers, ["restart_app"])
    XCTAssertEqual(notifications.removalRequests, 0)

    notifications.scheduleCompletion?(TestError.factoryMustNotRun)
    wait(for: [failed], timeout: 2)
    // Once no restart is pending, ordinary registration still removes stale
    // restart notifications left by an earlier launch.
    RestartAppPlugin.register(with: registrar, notificationService: notifications)
    XCTAssertTrue(notifications.pendingIdentifiers.isEmpty)
    XCTAssertEqual(notifications.removalRequests, 1)
  }

  private func restartCall(_ mode: String) -> FlutterMethodCall {
    FlutterMethodCall(methodName: "restartApp", arguments: ["mode": mode])
  }

  private func assertRestartError(
    _ code: String,
    mode: String,
    notifications: NotificationService = NotificationService(),
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let response = expectation(description: "\(mode) returns \(code)")
    RestartAppPlugin(notificationService: notifications).handle(restartCall(mode)) { value in
      XCTAssertEqual((value as? FlutterError)?.code, code, file: file, line: line)
      response.fulfill()
    }
    wait(for: [response], timeout: 2)
  }

  func testFactoryFailureKeepsCurrentEngineAndAllowsAnotherRequest() throws {
    let window = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }.first { $0.isKeyWindow }
    )
    let controller = try XCTUnwrap(window.rootViewController as? FlutterViewController)
    let engine = try XCTUnwrap(controller.engine)
    var factoryCalls = 0
    RestartAppPlugin.setEngineFactory(
      {
        factoryCalls += 1
        throw TestError.factoryMustNotRun
      }, windowProvider: { window }
    )
    let accepted = expectation(description: "restart scheduled")
    let duplicate = expectation(description: "duplicate rejected")
    let plugin = RestartAppPlugin()
    let call = FlutterMethodCall(
      methodName: "restartApp", arguments: ["mode": "flutterEngine", "structuredResult": true]
    )
    plugin.handle(call) { value in
      XCTAssertEqual((value as? [String: Any])?["success"] as? Bool, true)
      accepted.fulfill()
      plugin.handle(call) { value in
        XCTAssertEqual((value as? FlutterError)?.code, "IOS_RESTART_ALREADY_IN_PROGRESS")
        duplicate.fulfill()
      }
    }
    wait(for: [accepted, duplicate], timeout: 2)

    let failed = expectation(description: "factory failure handled")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      XCTAssertEqual(factoryCalls, 1)
      XCTAssertTrue(window.rootViewController === controller)
      XCTAssertTrue(controller.engine === engine)
      XCTAssertNotNil(engine.isolateId)
      failed.fulfill()
    }
    wait(for: [failed], timeout: 2)

    RestartAppPlugin.setEngineFactory(
      { throw TestError.factoryMustNotRun }, windowProvider: { nil }
    )
    let recovered = expectation(description: "no stale in-progress flag")
    plugin.handle(call) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "IOS_NO_ACTIVE_WINDOW")
      recovered.fulfill()
    }
    wait(for: [recovered], timeout: 2)
  }

  func testUnavailableCustomWindowDoesNotRestartAnotherScene() {
    RestartAppPlugin.setEngineFactory(
      { throw TestError.factoryMustNotRun }, windowProvider: { nil }
    )
    let response = expectation(description: "missing selected window response")
    RestartAppPlugin().handle(
      FlutterMethodCall(methodName: "restartApp", arguments: ["mode": "flutterEngine"])
    ) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "IOS_NO_ACTIVE_WINDOW")
      response.fulfill()
    }
    wait(for: [response], timeout: 2)
  }

  func testProcessRestartIsRejected() {
    let response = expectation(description: "unsupported process restart response")
    RestartAppPlugin().handle(
      FlutterMethodCall(methodName: "restartApp", arguments: ["mode": "process"])
    ) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "IOS_PROCESS_RESTART_UNSUPPORTED")
      response.fulfill()
    }
    wait(for: [response], timeout: 2)
  }

  func testUnknownModeDoesNotStartRestart() {
    let response = expectation(description: "unsupported mode response")
    RestartAppPlugin().handle(
      FlutterMethodCall(methodName: "restartApp", arguments: ["mode": "unknownMode"])
    ) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "UNSUPPORTED_RESTART_MODE")
      response.fulfill()
    }
    wait(for: [response], timeout: 2)
  }

  func testReconfigurationRestoresDefaultRootProtection() {
    let window = UIWindow(frame: UIScreen.main.bounds)
    window.rootViewController = UIViewController()
    RestartAppPlugin.setEngineFactory(
      { throw TestError.factoryMustNotRun },
      windowProvider: { window },
      viewControllerInstaller: { _, _ in }
    )
    RestartAppPlugin.setEngineFactory(
      { throw TestError.factoryMustNotRun }, windowProvider: { window }
    )
    let response = expectation(description: "unsafe root response")
    RestartAppPlugin().handle(
      FlutterMethodCall(methodName: "restartApp", arguments: ["mode": "flutterEngine"])
    ) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "IOS_UNSAFE_ROOT_REPLACEMENT")
      response.fulfill()
    }
    wait(for: [response], timeout: 2)
  }
}

private final class SelectionWindow: UIWindow {
  var reportsKeyWindow = false
  override var isKeyWindow: Bool { reportsKeyWindow }
}

private final class NotificationService: RestartNotificationService {
  var status: UNAuthorizationStatus? = .denied
  var authorizationResponse: (Bool, Error?)? = (false, nil)
  var holdScheduleCompletion = false
  var statusRequests = 0
  var removalRequests = 0
  var pendingIdentifiers: [String] = []
  var statusCompletion: ((UNAuthorizationStatus) -> Void)?
  var authorizationCompletion: ((Bool, Error?) -> Void)?
  var scheduleCompletion: ((Error?) -> Void)?
  var onStatusRequest: (() -> Void)?
  var onAuthorizationRequest: (() -> Void)?
  var onScheduleRequest: (() -> Void)?

  func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
    statusRequests += 1
    statusCompletion = completion
    onStatusRequest?()
    if let status = status { completion(status) }
  }

  func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
    authorizationCompletion = completion
    onAuthorizationRequest?()
    if let response = authorizationResponse { completion(response.0, response.1) }
  }

  func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
    pendingIdentifiers.append(request.identifier)
    scheduleCompletion = completion
    onScheduleRequest?()
    // Test doubles never authorize a real process exit, even if a test forgets
    // to supply its intended failure callback.
    if !holdScheduleCompletion {
      completion(NSError(domain: "RunnerTests", code: 1))
    }
  }

  func removePendingRestartNotification() {
    removalRequests += 1
    pendingIdentifiers.removeAll { $0 == "restart_app" }
  }
}
