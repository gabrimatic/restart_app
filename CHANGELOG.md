## 1.5.1

* Added `forceKill` option for Android — fully terminates the process after restart for a clean cold start
* Fixed iOS restart not working due to incorrect AppDelegate cast
* Implemented proper iOS restart using local notifications with permission handling
* **Breaking (iOS):** Returns a `PlatformException` with code `NOTIFICATION_DENIED` if notification permission is denied — handle this in your code
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

* Updated JVM and Kotlin versions.
* Upgraded Flutter web dependency to more compatible version
* Resolved dependency conflicts with firebase packages and restart_app.


## 1.3.0

* Custom notification support added for iOS:
  - `notificationTitle` and `notificationBody` can now be customized.
* Android improvements:
  - Added namespace configuration.
  - Replaced `.exit` method with new, safe `ActivityAware` method.
  - Updated Kotlin version.
* Web support enhanced:
  - Added Wasm support.
* General updates:
  - Updated dependencies.

## 1.2.1
 
* In-code documentation added to the source.

## 1.2.0
 
* iOS support added.
 
## 1.1.3
 
* Updated to Flutter 3.10.
* Example files updated.
 
## 1.1.2
 
* Updated to Flutter 3.7.0.
 
## 1.1.1+1
 
* iOS support description added to README.

## 1.1.1
 
* Gradle version updated. 

## 1.1.0+1
 
* Updated to Flutter 3.0.0. 

## 1.1.0 
 
* Web support added.

## 1.0.3

* Plugin version updated in README.

## 1.0.2

* Package name updated in example files.

## 1.0.1

* Package name updated.

## 1.0.0

* Null-Safety support added.
