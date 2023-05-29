# Restart app in Flutter


A Flutter plugin that helps you to restart the whole Flutter app with a single function call by using **Native APIs**.


## How to use it?
**1.  Add the package to pubspec.yaml dependency:**

```yaml
dependencies:
  restart_app: ^1.2.1
```

**2. Import package:**

```dart
import 'package:restart_app/restart_app.dart';
```

**3. Call the restartApp method where ever you want:**

```dart
onPressed: () {
  /// Fill webOrigin only when your new origin is different than the app's origin
  Restart.restartApp(webOrigin: '[your main route]');
}
```

## iOS Platform Config
In order to restart your Flutter application on iOS, due to the platform's limitations, the app will exit and send a local notification to the user. The user can then tap this notification to reopen the app.
This is not a full app restart, but it's the **closest workaround possible** on iOS.

Please note, this package requests local notification permissions just before the app restarts. If granted, a notification will be displayed to the user, prompting them to reopen the app. 

While this permission request is handled within the swift code by default, it's recommended that you handle the notification permissions at an earlier point in your app's lifecycle.
It's because there could be a delay in iOS granting notification permissions, especially if the user needs to manually allow it in their device's settings. Furthermore, if permissions are requested without context, the user might deny them, resulting in a poor user experience. 

To handle the notification permissions earlier and provide context to the user, you can use packages like [permission_handler](https://pub.dev/packages/permission_handler "permission_handler").

**Here's the configuration you need to add:**

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

## TODO
- Implement deep linking for smooth app restarts, enabling direct navigation to specific pages upon restart.

## Developer
By [Hossein Yousefpour](https://gabrimatic.info "Hossein Yousefpour")

&copy; All rights reserved.

## Donate
<a href="https://www.buymeacoffee.com/gabrimatic" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Book" style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;-webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;" ></a>
