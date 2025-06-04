## 1.4.0
* **Breaking Changes**: Added new optional parameters to `restartApp()`:
  - `delayBeforeRestart`: Adds configurable delay before restart (addresses issue #46)
  - `forceKill`: Forces complete process restart for better cleanup (addresses issue #38)
* **Web Platform Improvements**:
  - Fixed PlatformException type casting error (addresses issue #35)
  - Added proper hash URL strategy support for single-page applications (addresses issue #14)
  - Improved error handling and backward compatibility
* **Android Platform Improvements**:
  - Enhanced cleanup process with force kill option for proper device disconnection
  - Fixed platform message response detachment issues (addresses issue #45)
  - Added configurable restart delay
  - Better error handling for RTSP streams and platform view issues (addresses issue #41)
* **iOS Platform Improvements**:
  - Custom notification icons instead of default Flutter icon (addresses issue #40)
  - Enhanced notification permission handling
  - Better URL scheme support for app reopening
  - Configurable restart delays
* **Development Experience**:
  - Lowered minimum SDK requirements to support more projects (addresses issue #36)
  - Added proper main isolate validation (addresses issue #19)
  - Improved error messages and debugging information
  - Enhanced platform detection and unsupported platform handling
* **Documentation and Examples**:
  - Updated README with new parameter usage
  - Added comprehensive error handling examples
  - Improved platform-specific configuration documentation

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
