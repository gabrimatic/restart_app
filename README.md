# Restart app in Flutter

A Flutter plugin that restarts the whole Flutter app with a single function call, using native APIs on each platform.

## Usage
**1.  Add the package to pubspec.yaml dependency:**

```yaml
dependencies:
  restart_app: ^1.4.0
```

**2. Import package:**

```dart
import 'package:restart_app/restart_app.dart';
```

**3. Call the restartApp method wherever you want:**

```dart
onPressed: () {
	Restart.restartApp(
		/// In Web Platform, Fill webOrigin only when your new origin is different than the app's origin
		// webOrigin: 'http://example.com',

		// Customizing the restart notification message (only needed on iOS)
		notificationTitle: 'Restarting App',
		notificationBody: 'Please tap here to open the app again.',
		
		// Optional: Add delay before restart (in milliseconds)
		delayBeforeRestart: 1000, // 1 second delay
		
		// Optional: Force complete app termination for better cleanup (Android only)
		forceKill: false,
	);
}
```

## New in v1.4.0

### Additional parameters

`restartApp()` now accepts:

- **`delayBeforeRestart`** (int): delay in milliseconds before restart. Useful for cleanup or showing user feedback.
- **`forceKill`** (bool): forces process termination on Android, helpful for cleaning up device connections.

### Web platform

- **Hash URL strategy support**: handles single-page apps with hash-based routing.
- **Error handling**: fixed type-casting issues and improved error messages.

### Usage Examples

```dart
// Standard restart
Restart.restartApp();

// Restart with delay
Restart.restartApp(delayBeforeRestart: 2000);

// Force kill restart (Android) - useful for device connection cleanup
Restart.restartApp(forceKill: true);

// Web with hash routing
Restart.restartApp(webOrigin: '#/home');

// Combined parameters
Restart.restartApp(
  delayBeforeRestart: 1500,
  forceKill: true,
  notificationTitle: 'App Restarting',
  notificationBody: 'Please wait while we restart the app...',
);
```

## iOS platform config

Due to platform limitations on iOS, the app exits and sends a local notification. The user taps the notification to reopen the app. This is the closest available workaround on iOS.

##### Customization:
You can configure the notification’s title and body by passing the `notificationTitle` and `notificationBody` parameters to the `.restartApp` method. These parameters allow you to customize the content of the local notification triggered upon app exit.

##### Notification Permission:
RestartApp package requests local notification permissions just before the app restarts. If granted, a notification will be displayed to the user, prompting them to reopen the app. 

While this permission request is handled within the swift code by default, it's recommended that you handle the notification permissions at an earlier point in your app's lifecycle.
This is because there could be a delay in iOS granting notification permissions, especially if the user needs to manually allow it in their device's settings. Furthermore, if permissions are requested without context, the user might deny them, resulting in a poor user experience. 

To handle notification permissions earlier and provide context to the user, you can use packages like [permission_handler](https://pub.dev/packages/permission_handler "permission_handler").

Add the following to `/ios/Runner/Info.plist`. This will allow the app to send local notifications. Replace PRODUCT_BUNDLE_IDENTIFIER and example with your actual bundle identifier and URL scheme:

```
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLName</key>
	<!-- You can find it on /ios/project.pbxproj - 'PRODUCT_BUNDLE_IDENTIFIER' -->
    <string>[Your project PRODUCT_BUNDLE_IDENTIFIER value]</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <!-- Your app title -->
      <string>example</string>
    </array>
  </dict>
</array>
```

> The CFBundleURLTypes key is used to define URL schemes that your app can handle. URL schemes are used to open your app from another app, a webpage, or even the same app. In this case, it is used to reopen the app from the local notification.


## Developer
By [Hossein Yousefpour](https://gabrimatic.info "Hossein Yousefpour")

&copy; All rights reserved.

## Donate
<a href="https://www.buymeacoffee.com/gabrimatic" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Book" style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;-webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;" ></a>
