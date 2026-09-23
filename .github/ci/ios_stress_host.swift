import Darwin
import Flutter
import ObjectiveC.runtime
import UIKit
import WebKit
import restart_app

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    StressRecorder.shared.start()
    RestartAppPlugin.configureEngineRestart(
      registerPlugins: { engine in
        GeneratedPluginRegistrant.register(with: engine)
        StressRecorder.shared.register(engine: engine)
      },
      beforeRestart: { StressRecorder.shared.captureCurrent() }
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ bridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: bridge.pluginRegistry)
    if let registrar = bridge.pluginRegistry.registrar(forPlugin: "RestartStressRecorder") {
      StressRecorder.shared.install(messenger: registrar.messenger())
    }
  }
}

private final class WeakEntry<T: AnyObject> {
  weak var object: T?
  let id: Int
  var destructionRequested = false
  var destructionCompleted = false

  init(_ object: T, id: Int) {
    self.object = object
    self.id = id
  }
}

private final class StressRecorder {
  static let shared = StressRecorder()
  private let configuration: [String: Any] = [
    "runID": "__RUN_ID__", "cycles": __CYCLES__, "settleMilliseconds": 2000,
    "archiveSHA256": "__ARCHIVE_SHA__", "resolvedPackageRoot": "__PACKAGE_ROOT__",
  ]
  private var engines: [WeakEntry<FlutterEngine>] = []
  private var controllers: [WeakEntry<FlutterViewController>] = []
  private var webViews: [WeakEntry<WKWebView>] = []
  private var finalResult: [String: Any]?
  private var intercepting = false

  private var window: UIWindow? {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }
      .flatMap { $0.windows }.first { $0.isKeyWindow }
  }

  private func track<T: AnyObject>(_ object: T, in entries: inout [WeakEntry<T>]) -> WeakEntry<T> {
    if let previous = entries.first(where: { $0.object === object }) { return previous }
    let entry = WeakEntry(object, id: entries.count + 1)
    entries.append(entry)
    return entry
  }

  func start() {
    guard !intercepting,
      let original = class_getInstanceMethod(
        FlutterEngine.self, #selector(FlutterEngine.destroyContext)),
      let replacement = class_getInstanceMethod(
        FlutterEngine.self, #selector(FlutterEngine.stressDestroyContext))
    else { return }
    method_exchangeImplementations(original, replacement)
    intercepting = true
  }

  private func restoreInterception() {
    guard intercepting,
      let original = class_getInstanceMethod(
        FlutterEngine.self, #selector(FlutterEngine.destroyContext)),
      let replacement = class_getInstanceMethod(
        FlutterEngine.self, #selector(FlutterEngine.stressDestroyContext))
    else { return }
    method_exchangeImplementations(original, replacement)
    intercepting = false
  }

  func requestedDestruction(_ engine: FlutterEngine) -> Int {
    let entry = track(engine, in: &engines)
    entry.destructionRequested = true
    return entry.id
  }

  func completedDestruction(_ id: Int) {
    engines.first { $0.id == id }?.destructionCompleted = true
  }

  func register(engine: FlutterEngine) {
    _ = track(engine, in: &engines)
    engine.ensureSemanticsEnabled()
    install(messenger: engine.binaryMessenger)
  }

  func captureCurrent() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    _ = track(controller, in: &controllers)
    let engine = controller.engine
    _ = track(engine, in: &engines)
    engine.ensureSemanticsEnabled()
    if let view = controller.viewIfLoaded { collectWebViews(view) }
  }

  private func collectWebViews(_ view: UIView) {
    if let webView = view as? WKWebView { _ = track(webView, in: &webViews) }
    for child in view.subviews { collectWebViews(child) }
  }

  private func nativeSnapshot() -> [String: Any] {
    captureCurrent()
    let currentController = window?.rootViewController as? FlutterViewController
    let currentEngine = currentController?.engine
    let currentID = engines.first { $0.object === currentEngine }?.id ?? 0
    let old = engines.filter { $0.id != currentID }
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return [
      "pid": ProcessInfo.processInfo.processIdentifier,
      "uptime": ProcessInfo.processInfo.systemUptime,
      "applicationState": UIApplication.shared.applicationState == .active ? "active" : "inactive",
      "currentEngineID": currentID,
      "enginesCreated": engines.count,
      "liveEngineWrappers": engines.filter { $0.object != nil }.count,
      "oldUndestroyedEngines": old.filter { !$0.destructionCompleted }.count,
      "destructionRequests": engines.filter { $0.destructionRequested }.count,
      "destructionCompletions": engines.filter { $0.destructionCompleted }.count,
      "retainedDestroyedEngineIDs": old.filter { $0.object != nil && $0.destructionCompleted }.map {
        $0.id
      },
      "liveControllers": controllers.filter { $0.object != nil }.count,
      "oldLiveControllers": controllers.filter {
        $0.object != nil && $0.object !== currentController
      }.count,
      "oldLiveControllerIDs": controllers.filter {
        $0.object != nil && $0.object !== currentController
      }.map { $0.id },
      "liveWebViews": webViews.filter { $0.object != nil }.count,
      "oldLiveWebViewIDs": webViews.filter {
        guard let view = $0.object, let root = currentController?.viewIfLoaded else { return false }
        return !view.isDescendant(of: root)
      }.map { $0.id },
      "webViewsCreated": webViews.count,
      "webViewGeometry": webViews.compactMap { entry -> [String: Any]? in
        guard let view = entry.object else { return nil }
        return [
          "id": entry.id,
          "offsetX": view.scrollView.contentOffset.x,
          "offsetY": view.scrollView.contentOffset.y,
          "contentWidth": view.scrollView.contentSize.width,
          "contentHeight": view.scrollView.contentSize.height,
          "viewWidth": view.bounds.width,
          "viewHeight": view.bounds.height,
          "insetTop": view.scrollView.adjustedContentInset.top,
          "insetBottom": view.scrollView.adjustedContentInset.bottom,
          "isAttached": view.window != nil,
        ]
      },
      "memoryStatus": status,
      "residentBytes": info.resident_size,
      "physFootprintBytes": info.phys_footprint,
    ]
  }

  private func save() throws {
    var report: [String: Any] = [
      "configuration": configuration,
      "iosVersion": UIDevice.current.systemVersion,
      "bundleID": Bundle.main.bundleIdentifier ?? "",
      "eventsFile": "restart-stress-events.jsonl",
    ]
    if let finalResult = finalResult { report["result"] = finalResult }
    let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let data = try JSONSerialization.data(
      withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: folder.appendingPathComponent("restart-stress.json"), options: .atomic)
  }

  private func append(_ event: [String: Any]) throws {
    let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let file = folder.appendingPathComponent("restart-stress-events.jsonl")
    if !FileManager.default.fileExists(atPath: file.path) {
      FileManager.default.createFile(atPath: file.path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: file)
    defer { handle.closeFile() }
    handle.seekToEndOfFile()
    var stamped = event
    stamped["runID"] = configuration["runID"]
    var data = try JSONSerialization.data(withJSONObject: stamped, options: [.sortedKeys])
    data.append(0x0a)
    handle.write(data)
    handle.synchronizeFile()
  }

  func install(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "restart_app/stress", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      do {
        switch call.method {
        case "configuration": result(self.configuration)
        case "snapshot": result(self.nativeSnapshot())
        case "record":
          guard let event = call.arguments as? [String: Any] else {
            result(FlutterError(code: "BAD_EVENT", message: "Expected a map", details: nil))
            return
          }
          try self.append(event)
          try self.save()
          result(nil)
        case "finish":
          self.finalResult = call.arguments as? [String: Any]
          try self.save()
          self.restoreInterception()
          result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "EVIDENCE_WRITE_FAILED", message: "\(error)", details: nil))
      }
    }
  }
}

extension FlutterEngine {
  @objc fileprivate func stressDestroyContext() {
    let id = StressRecorder.shared.requestedDestruction(self)
    // After exchange, this forwards to Flutter's original implementation once.
    stressDestroyContext()
    StressRecorder.shared.completedDestruction(id)
  }
}
