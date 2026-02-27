# Restart app in Flutter


A Flutter plugin that helps you to restart the whole Flutter app with a single function call by using **Native APIs**.


## How to use it?
**1.  Add the package to pubspec.yaml dependency:**

```yaml
dependencies:
  restart_app: ^1.5.2
```

**2. Import package:**

```dart
import 'package:restart_app/restart_app.dart';
```

**3. Call the restartApp method wherever you want:**

```dart
onPressed: () {
	Restart.restartApp(
		/// Web: fill webOrigin only when your new origin differs from the app's origin
		// webOrigin: 'http://example.com',

		/// iOS: customize the local notification shown after the app exits
		notificationTitle: 'Restarting App',
		notificationBody: 'Please tap here to open the app again.',

		/// Android: set to true for a full cold restart (kills the process)
		// forceKill: true,
	);
}
```

## iOS Platform Notes

On iOS, apps cannot restart themselves programmatically due to platform sandboxing. When `restartApp()` is called, the plugin schedules a local notification and then exits the app via `exit(0)`. The user taps the notification to reopen the app.

This is the closest possible workaround on iOS. It is not a fully automatic restart.

#### Notification content

Customize the notification shown to the user with `notificationTitle` and `notificationBody`:

```dart
Restart.restartApp(
  notificationTitle: 'Update applied',
  notificationBody: 'Tap to reopen the app.',
);
```

#### Notification permission

The plugin requests notification permission immediately before restarting. If the user has not yet granted permission, iOS will show the system permission prompt at that moment, which can feel abrupt and may result in a denial.

It is strongly recommended to request notification permission earlier in your app's lifecycle, with appropriate context, so it is already granted when `restartApp()` is called. The [permission_handler](https://pub.dev/packages/permission_handler) package can help with this.

If the user has denied notification permission, `restartApp()` throws a `PlatformException` with code `NOTIFICATION_DENIED`. Handle this in your code:

```dart
try {
  await Restart.restartApp();
} on PlatformException catch (e) {
  if (e.code == 'NOTIFICATION_DENIED') {
    // Prompt the user to enable notifications in Settings
  }
}
```

#### IPA build and provisioning profiles

`restart_app` uses **local notifications only** and does not require the Push Notifications capability. It does not add any push-related entitlements to your app.

If you see the error `"requires a provisioning profile with the Push Notifications feature"` when exporting an IPA, this is caused by another dependency in your project, most commonly `firebase_messaging`, which requires push notification entitlements. The fix is to ensure your distribution provisioning profile includes the Push Notifications capability. This is unrelated to `restart_app`.

## Calling from a background isolate

`Restart.restartApp()` uses a platform channel and must be called from the **main isolate**. Calling it directly from a background isolate will throw:

```
Bad state: The BackgroundIsolateBinaryMessenger.instance value is invalid
until BackgroundIsolateBinaryMessenger.ensureInitialized is executed.
```

The recommended pattern is to send a message from your isolate to the main isolate and call `restartApp()` there:

```dart
// In your main isolate, set up a ReceivePort to listen for restart signals:
final receivePort = ReceivePort();
receivePort.listen((message) {
  if (message == 'restart') {
    Restart.restartApp();
  }
});

// Pass the SendPort to your isolate:
await Isolate.spawn(myIsolateFunction, receivePort.sendPort);

// In your isolate, send the signal instead of calling restartApp() directly:
void myIsolateFunction(SendPort sendPort) {
  // ... your background work ...
  sendPort.send('restart');
}
```

If you need to call platform channels directly from a background isolate for other reasons, you can initialize `BackgroundIsolateBinaryMessenger` first, but the `SendPort` pattern above is simpler and more reliable.

## Developer
Created by [Soroush Yousefpour](https://gabrimatic.info)

&copy; All rights reserved.

## Donate
<a href="https://www.buymeacoffee.com/gabrimatic" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Book" style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;-webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;" ></a>
