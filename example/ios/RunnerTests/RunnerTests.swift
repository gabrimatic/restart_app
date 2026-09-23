import Flutter
import UIKit
import XCTest
import restart_app

@MainActor
class RunnerTests: XCTestCase {
  private enum TestError: Error { case factoryMustNotRun }

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
