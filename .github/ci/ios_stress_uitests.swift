import XCTest

final class RestartStressUITests: XCTestCase {
  func testRepeatedEngineRestartsAndHomeResume() {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "info.gabrimatic.restartapp.stress")
    app.launch()
    for cycle in stride(from: 10, through: __CYCLES__, by: 10) {
      let checkpoint = app.staticTexts["WAIT_BACKGROUND \(cycle)"]
      XCTAssertTrue(checkpoint.waitForExistence(timeout: 240), app.debugDescription)
      XCUIDevice.shared.press(.home)
      XCTAssertTrue(app.wait(for: .runningBackground, timeout: 15))
      // Keep a real background interval at every lifecycle checkpoint.
      let background = expectation(description: "background interval")
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) { background.fulfill() }
      wait(for: [background], timeout: 5)
      app.activate()
      XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    }
    XCTAssertTrue(
      app.staticTexts["PASS cycles=__CYCLES__"].waitForExistence(timeout: 120), app.debugDescription
    )
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }
}
