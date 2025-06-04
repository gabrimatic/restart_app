# Restart app in Flutter


A Flutter plugin that helps you to restart the whole Flutter app with a single function call by using **Native APIs**.


## How to use it?
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

### Enhanced Parameters

The `restartApp()` method now supports additional optional parameters:

- **`delayBeforeRestart`** (int): Delay in milliseconds before the restart occurs. Useful for cleanup operations or showing user feedback.
- **`forceKill`** (bool): Forces complete process termination on Android for better cleanup of resources like device connections.

### Web Platform Improvements

- **Hash URL Strategy Support**: Properly handles single-page applications with hash-based routing
- **Better Error Handling**: Fixed type casting issues and improved error messages

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

## iOS Platform Config
In order to restart your Flutter application on iOS, due to the platform's limitations, the app will exit and send a local notification to the user. The user can then tap this notification to reopen the app.
This is not a full app restart, but it's the **closest workaround possible** on iOS.

##### Customization:
You can configure the notification’s title and body by passing the `notificationTitle` and `notificationBody` parameters to the `.restartApp` method. These parameters allow you to customize the content of the local notification triggered upon app exit.

##### Notification Permission:
RestartApp package requests local notification permissions just before the app restarts. If granted, a notification will be displayed to the user, prompting them to reopen the app. 

While this permission request is handled within the swift code by default, it's recommended that you handle the notification permissions at an earlier point in your app's lifecycle.
This is because there could be a delay in iOS granting notification permissions, especially if the user needs to manually allow it in their device's settings. Furthermore, if permissions are requested without context, the user might deny them, resulting in a poor user experience. 

To handle the notification permissions earlier and provide context to the user, you can use packages like [permission_handler](https://pub.dev/packages/permission_handler "permission_handler").

**Here is the configuration you need to add:**

Add the following to the project /ios/Runner/Info.plist file. This will allow the app to send local notifications. Replace PRODUCT_BUNDLE_IDENTIFIER and example with your actual bundle identifier and URL scheme:

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
