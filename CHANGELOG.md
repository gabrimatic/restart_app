## 1.8.3

* Made `Restart.restartApp(...)` the single Dart restart entry point
* Changed `Restart.restartApp(...)` to return `RestartResult`, giving one call with `success`, resolved `mode`, `code`, and `message`
* Kept all restart customization on `Restart.restartApp(...)`: `mode`, `webOrigin`, `forceKill`, `notificationTitle`, and `notificationBody`
* Refined the example so `main.dart` shows the restart calls directly, while package survival checks live in focused helper files
* Updated README and example docs so the quick start is platform-neutral and iOS details stay in the iOS section

## 1.8.2

* Tightened iOS default behavior: `platformDefault` now fails cleanly when engine restart is not configured instead of quietly using notification + `exit(0)`
* Kept notification restart as an explicit `RestartMode.notificationFallback` path for apps that accept the permission prompt, exit, and user-tap tradeoff
* Removed the internal implicit-fallback flag from the Dart API and iOS platform-channel payload
* Expanded the example with package checks that exercise common plugin paths after restart
* Clarified README language around iOS engine restart versus unsupported full process restart

## 1.8.1

* Fixed mode handling so unsupported restart modes fail with a clear platform error instead of silently falling back
* Returned the resolved restart mode from Android, web, Linux, macOS, and Windows
* Made Android `RestartMode.process` use the full `forceKill` path automatically
* Updated the example Android Gradle project for current Java and Flutter toolchains
* Moved the iOS `beforeRestart` hook before replacement engine creation so apps can clean up native resources first

## 1.8.0

* Added structured restart types with `RestartResult`, `RestartMode`, and `Restart.restartCapability()`
* Added opt-in iOS Flutter engine restart: fresh `FlutterEngine`, Dart entrypoint rerun, host plugin registration, root `FlutterViewController` replacement, and old engine teardown
* Kept the existing iOS notification + `exit(0)` behavior as an explicit legacy fallback
* Documented the important iOS boundary: Flutter engine restart is supported, automatic full process restart is not available through public iOS APIs

## 1.7.3

* Fixed Xcode build failure caused by SPM target path resolving outside the package root ([#52](https://github.com/gabrimatic/restart_app/issues/52))

## 1.7.2

* Fixed Swift Package Manager file locations for iOS and macOS

## 1.7.1

* Added Swift Package Manager support for iOS and macOS

## 1.7.0

* Added native Linux support. Restarts via `execv`, replacing the current process in-place
* Added native Windows support. Launches a new instance via `CreateProcess` and exits
* Added Android TV and Fire TV support via leanback launcher fallback
* `restartApp()` now returns `false` on native errors instead of throwing `PlatformException`
* Added CI with code quality checks, formatting, and native linting (Kotlin, Swift, C++)
* Added unit tests

## 1.6.0

* Added native macOS support via a Swift plugin. Restarts the app by launching a new instance using `NSWorkspace` and terminating the current process

## 1.5.2

* Fixed Android FlutterJNI detached error: all destructive restart operations are now deferred via a short delay so the platform channel result can be delivered to the Dart side before the Flutter engine is torn down
* Lowered minimum Dart SDK requirement from 3.5.1 to 3.4.0 (Flutter 3.22+)
* Improved README: corrected iOS provisioning profile guidance, removed inaccurate CFBundleURLTypes instructions, and added documentation for calling from background isolates

## 1.5.1

* Added `forceKill` option for Android. Fully terminates the process after restart for a clean cold start
* Fixed iOS restart not working due to incorrect AppDelegate cast
* Implemented proper iOS restart using local notifications with permission handling
* **Breaking (iOS):** Returns a `PlatformException` with code `NOTIFICATION_DENIED` if notification permission is denied. Handle this in your code
* Removed unused `plugin_platform_interface` dependency
* Fixed iOS podspec placeholder metadata
* Fixed nested MaterialApp in example app
* Improved web error handling for unrecognized method calls
* Cleaned up unused imports

## 1.3.3

* Fixed web platform crash caused by argument type mismatch ([#35](https://github.com/gabrimatic/restart_app/issues/35), [#51](https://github.com/gabrimatic/restart_app/issues/51))
* Fixed web hash URL strategy not working ([#14](https://github.com/gabrimatic/restart_app/issues/14))
* Fixed Android crash when launch intent is unavailable ([#50](https://github.com/gabrimatic/restart_app/issues/50))
* Fixed iOS `restartApp()` always returning false ([#48](https://github.com/gabrimatic/restart_app/issues/48))

## 1.3.2

* Updated web package to the stable version

## 1.3.1

* Updated JVM and Kotlin versions
* Upgraded Flutter web dependency to more compatible version
* Resolved dependency conflicts with firebase packages and restart_app

## 1.3.0

* Custom notification support added for iOS:
  - `notificationTitle` and `notificationBody` can now be customized
* Android improvements:
  - Added namespace configuration
  - Replaced `.exit` method with new, safe `ActivityAware` method
  - Updated Kotlin version
* Web support enhanced:
  - Added Wasm support
* General updates:
  - Updated dependencies

## 1.2.1

* In-code documentation added to the source

## 1.2.0

* iOS support added

## 1.1.3

* Updated to Flutter 3.10
* Example files updated

## 1.1.2

* Updated to Flutter 3.7.0

## 1.1.1+1

* iOS support description added to README

## 1.1.1

* Gradle version updated

## 1.1.0+1

* Updated to Flutter 3.0.0

## 1.1.0

* Web support added

## 1.0.3

* Plugin version updated in README

## 1.0.2

* Package name updated in example files

## 1.0.1

* Package name updated

## 1.0.0

* Null-Safety support added
