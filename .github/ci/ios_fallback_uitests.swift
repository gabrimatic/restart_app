import XCTest

final class NotificationFallbackUITests: XCTestCase {
  private let bundleID = "__BUNDLE_ID__"
  private let policy = "__POLICY__"

  private func attachment(_ name: String, text: String) {
    let item = XCTAttachment(string: text)
    item.name = name
    item.lifetime = .keepAlways
    add(item)
  }

  private func reveal(_ element: XCUIElement, in app: XCUIApplication, down: Bool) {
    for _ in 0..<8 {
      if element.exists && element.isHittable { return }
      let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: down ? 0.82 : 0.22))
      let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: down ? 0.22 : 0.82))
      start.press(forDuration: 0.05, thenDragTo: end)
    }
    XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
  }

  private func snapshot(_ app: XCUIApplication, name: String, previousBoot: String? = nil) throws
    -> [String: Any]
  {
    let card = app.otherElements.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Package restart checks\n")
    ).firstMatch
    // Flutter merges the card header into a noninteractive accessibility group.
    // Reading it does not require an activation point during engine replacement.
    XCTAssertTrue(card.waitForExistence(timeout: 30), app.debugDescription)
    var requirements = [
      NSPredicate(format: "label BEGINSWITH %@", "Package restart checks\n"),
      NSPredicate(format: "label CONTAINS %@", "\nAll checks passed\n"),
    ]
    if let previousBoot {
      requirements.append(NSPredicate(format: "NOT (label CONTAINS %@)", previousBoot))
    }
    let checks = app.otherElements.matching(
      NSCompoundPredicate(andPredicateWithSubpredicates: requirements)
    ).firstMatch
    XCTAssertTrue(checks.waitForExistence(timeout: 90), app.debugDescription)
    let fields = checks.label.components(separatedBy: "\n")
    let boot = try XCTUnwrap(fields.first { $0.hasPrefix("boot token: ") })
    let dirty = try XCTUnwrap(fields.first { $0.hasPrefix("dart dirty state: ") })
    let launches = try XCTUnwrap(fields.first { $0.hasPrefix("launches: ") })
    let attempts = try XCTUnwrap(fields.first { $0.hasPrefix("restart attempts: ") })
    var probes: [String: String] = [:]
    for probe in [
      "restart capability", "shared preferences", "package info", "connectivity",
      "url launcher", "http", "cache manager", "file storage", "sqflite", "device info", "webview",
      "dart clean state",
    ] {
      let result = app.staticTexts.matching(
        NSPredicate(format: "label BEGINSWITH %@", probe + ": pass\n")
      ).firstMatch
      reveal(result, in: app, down: true)
      XCTAssertTrue(result.exists, app.debugDescription)
      probes[probe] = result.label
    }
    let description = app.debugDescription
    attachment(name + "-hierarchy", text: description)
    let regex = try NSRegularExpression(pattern: "Application, [^\\n]*?pid: ([0-9]+)")
    let range = NSRange(description.startIndex..., in: description)
    let match = try XCTUnwrap(regex.firstMatch(in: description, range: range))
    let pidRange = try XCTUnwrap(Range(match.range(at: 1), in: description))
    let pid = try XCTUnwrap(Int(description[pidRange]))
    XCTAssertTrue(pid > 0)
    XCTAssertEqual(dirty, "dart dirty state: 0")
    XCTAssertTrue(boot.hasPrefix("boot token: "))
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = name
    image.lifetime = .keepAlways
    add(image)
    return [
      "pid": pid, "boot": boot, "dirty": dirty, "launches": launches,
      "attempts": attempts, "allChecksPassed": checks.exists, "probes": probes,
    ]
  }

  private func press(_ name: String, in app: XCUIApplication) {
    let button = app.buttons[name]
    reveal(button, in: app, down: false)
    button.tap()
  }

  func testPermissionAndRecovery() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: bundleID)
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    app.launch()
    let initial = try snapshot(app, name: "initial")
    XCTAssertEqual(initial["launches"] as? String, "launches: 1")
    press("iOS notification fallback", in: app)
    let alert = springboard.alerts.firstMatch
    XCTAssertTrue(alert.waitForExistence(timeout: 20), springboard.debugDescription)
    let prompt =
      alert.label + "\n"
      + alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "\n")
    XCTAssertTrue(prompt.contains("Restart Fallback " + policy.capitalized), prompt)
    XCTAssertTrue(prompt.lowercased().contains("notifications"), prompt)
    attachment("notification-permission", text: alert.debugDescription)
    var proof: [String: Any] = [
      "policy": policy, "bundleID": bundleID,
      "initial": initial, "permissionPromptObserved": true, "permissionPromptLabel": prompt,
    ]
    if policy == "denied" {
      let deny = alert.buttons.matching(
        NSPredicate(format: "label CONTAINS 'Allow' AND label != 'Allow'")
      ).firstMatch
      XCTAssertTrue(deny.exists, alert.debugDescription)
      deny.tap()
      let failure = app.staticTexts.matching(
        NSPredicate(format: "label BEGINSWITH 'NOTIFICATION_DENIED:'")
      ).firstMatch
      XCTAssertTrue(failure.waitForExistence(timeout: 15), app.debugDescription)
      let afterDenial = try snapshot(app, name: "after-denial")
      XCTAssertEqual(afterDenial["pid"] as? Int, initial["pid"] as? Int)
      XCTAssertEqual(afterDenial["boot"] as? String, initial["boot"] as? String)
      // The already-denied status must also return without exiting or retaining a guard.
      press("iOS notification fallback", in: app)
      XCTAssertTrue(
        app.staticTexts[
          "NOTIFICATION_DENIED: Notification permission is denied for the iOS notification fallback."
        ].waitForExistence(timeout: 15), app.debugDescription)
      XCTAssertFalse(springboard.alerts.firstMatch.exists)
      press("Engine restart (iOS)", in: app)
      let recovered = try snapshot(
        app, name: "engine-recovery", previousBoot: initial["boot"] as? String)
      XCTAssertEqual(recovered["pid"] as? Int, initial["pid"] as? Int)
      XCTAssertNotEqual(recovered["boot"] as? String, initial["boot"] as? String)
      XCTAssertEqual(recovered["launches"] as? String, "launches: 2")
      XCTAssertEqual(recovered["attempts"] as? String, "restart attempts: 3")
      proof["afterDenial"] = afterDenial
      proof["recovered"] = recovered
      proof["alreadyDeniedRejected"] = true
    } else {
      XCTAssertEqual(policy, "allowed")
      alert.buttons["Allow"].tap()
      XCTAssertTrue(app.wait(for: .notRunning, timeout: 20), app.debugDescription)
      proof["exitObserved"] = true
      let notification = springboard.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS 'Tap to reopen the example app.'")
      ).firstMatch
      XCTAssertTrue(notification.waitForExistence(timeout: 20), springboard.debugDescription)
      attachment("delivered-notification", text: springboard.debugDescription)
      proof["notificationLabel"] = notification.label
      notification.tap()
      XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), springboard.debugDescription)
      let reopened = try snapshot(
        app, name: "notification-reopened", previousBoot: initial["boot"] as? String)
      XCTAssertNotEqual(reopened["pid"] as? Int, initial["pid"] as? Int)
      XCTAssertNotEqual(reopened["boot"] as? String, initial["boot"] as? String)
      XCTAssertEqual(reopened["launches"] as? String, "launches: 2")
      XCTAssertEqual(reopened["attempts"] as? String, "restart attempts: 1")
      proof["reopened"] = reopened
      proof["actualNotificationTapped"] = true
    }
    app.terminate()
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), app.debugDescription)
    proof["cleanupStoppedApp"] = true
    proof["pass"] = true
    let data = try JSONSerialization.data(withJSONObject: proof, options: [.sortedKeys])
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    attachment("fallback-evidence", text: json)
    print("FALLBACK_EVIDENCE=" + json)
  }
}
