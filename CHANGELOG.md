## 1.10.1

* Simplified the README, guides, examples, and changelog; corrected documentation links.
* Clarified web routes, iOS setup, restart results, and Android requirements.
* Improved package descriptions and AI agent guidance, with a new documentation index.

## 1.10.0

* Fixed web restarts for identical URLs and fragment changes, including fragment removal.
* Preserved browser history replacement and HTML base URL resolution for restart destinations.
* Fixed documentation theme icons and resource loading in the static site.
* Improved the example's saved-data checks and restart testing across all six platforms.

## 1.9.2

* Added bundled AI agent skills for restart integration and iOS engine setup.
* Return `MISSING_PLUGIN` when native registration is missing, and handle invalid capability responses.
* Reject overlapping restart requests and allow retry after a failed restart.
* Fixed iOS custom-window selection, engine reconfiguration, and notification handling across engine registrations.
* Keep Linux running if relaunch fails; clean up failed Windows launches and report macOS launch failures.
* Updated the example for UIScene and expanded compatibility checks for Flutter, CocoaPods, SwiftPM, and AGP 9.

## 1.9.1

* Fixed AGP 9 builds failing with `Could not find method kotlin()`, including Flutter 3.44 projects ([#56](https://github.com/gabrimatic/restart_app/issues/56)).
* Support Kotlin configuration with AGP 9's built-in Kotlin either enabled or disabled.

## 1.9.0

**Upgrade notes:** Android now requires API 21, Java 17, AGP 8.1.4, and Kotlin 2.0.21. The iOS CocoaPods minimum is now iOS 12. Update older build configurations before upgrading.

**Web behavior change:** a restart now keeps the browser URL instead of opening the website root. Pass `webOrigin: '/'` to restart at the website root.

* Fixed Windows relaunch failures returning success.
* Preserved the requested mode when a platform returns an unknown mode, and handled malformed result fields.
* Fixed duplicate Android activity termination and prepared Kotlin setup for AGP 9.
* Aligned the iOS minimum across CocoaPods and SwiftPM, and moved macOS AppKit calls to the main thread.
* Added restart-mode examples and browser and desktop restart tests.

## 1.8.3

* **API change:** removed `Restart.restart()`. Use `Restart.restartApp()`, which now returns `Future<RestartResult>` instead of `Future<bool>`.
* Kept all options on that method: `mode`, `webOrigin`, `forceKill`, `notificationTitle`, and `notificationBody`.
* Simplified the example and setup documentation.

## 1.8.2

* Return a failed result when iOS engine restart is not configured, instead of falling back to notifications.
* Removed `iosLegacyNotificationFallback`; use `RestartMode.notificationFallback` to request notification relaunch.
* Added example checks for plugins after a restart.

## 1.8.1

* Reject unsupported modes and return the resolved mode on supported platforms.
* Made Android `RestartMode.process` use the force-kill path.
* Run the iOS `beforeRestart` hook before creating the replacement engine.
* Updated the example's Android build tools.

## 1.8.0

* Added `RestartResult`, `RestartMode`, and `Restart.restartCapability()`.
* Added iOS Flutter engine restart with native configuration, plugin registration, and old-engine cleanup.
* Kept notification relaunch as an explicit fallback. Automatic full process restart remains unsupported on iOS.

## 1.7.3

* Fixed the SwiftPM target path causing Xcode build failures ([#52](https://github.com/gabrimatic/restart_app/issues/52)).

## 1.7.2

* Fixed SwiftPM file locations for iOS and macOS.

## 1.7.1

* Added Swift Package Manager support for iOS and macOS.

## 1.7.0

* Added Linux and Windows support.
* Added Android TV and Fire TV support.
* Changed native failures to return `false` instead of throwing `PlatformException`.
* Added automated checks and unit tests.

## 1.6.0

* Added native macOS app relaunch support.

## 1.5.2

* Fixed Android FlutterJNI errors by delivering the result before tearing down the engine.
* Lowered the Dart minimum to 3.4.0 (Flutter 3.22 or later).
* Corrected iOS setup instructions and documented background-isolate use.

## 1.5.1

* Added Android `forceKill` and fixed iOS notification relaunch.
* **Breaking change on iOS:** denied notification permission now throws `PlatformException` with code `NOTIFICATION_DENIED`.
* Removed the unused `plugin_platform_interface` dependency and corrected package metadata and examples.

## 1.3.3

* Fixed web argument parsing crashes ([#35](https://github.com/gabrimatic/restart_app/issues/35), [#51](https://github.com/gabrimatic/restart_app/issues/51)) and hash routing ([#14](https://github.com/gabrimatic/restart_app/issues/14)).
* Fixed Android crashes when no launch intent is available ([#50](https://github.com/gabrimatic/restart_app/issues/50)).
* Fixed iOS `restartApp()` always returning `false` ([#48](https://github.com/gabrimatic/restart_app/issues/48)).

## 1.3.2

* Updated to the stable `web` package.

## 1.3.1

* Updated JVM, Kotlin, and web dependencies; resolved Firebase dependency conflicts.

## 1.3.0

* Added custom iOS notification titles and messages.
* Added web WebAssembly support.
* Updated Android namespace, Kotlin, and activity handling.

## 1.2.1

* Added API documentation.

## 1.2.0

* Added iOS support.

## 1.1.3

* Updated to Flutter 3.10 and refreshed the example.

## 1.1.2

* Updated to Flutter 3.7.

## 1.1.1+1

* Documented iOS support.

## 1.1.1

* Updated Gradle.

## 1.1.0+1

* Updated to Flutter 3.0.

## 1.1.0

* Added web support.

## 1.0.3

* Updated the README version.

## 1.0.2

* Updated the package name in examples.

## 1.0.1

* Updated the package name.

## 1.0.0

* Added null safety.
