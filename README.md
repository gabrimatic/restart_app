# Restart app in Flutter


A Flutter plugin that helps you to restart the whole Flutter app with a single function call by using **Native APIs**.


## How to use it?
**1.  Add the package to pubspec.yaml dependency:**

```yaml
dependencies:
  restart_app: ^1.4.0-beta
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
	);
}
```

## Developer
By [Hossein Yousefpour](https://gabrimatic.info "Hossein Yousefpour")

&copy; All rights reserved.

## Donate
<a href="https://www.buymeacoffee.com/gabrimatic" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Book" style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;-webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;" ></a>
