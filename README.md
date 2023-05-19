# Restart app in Flutter


A simple plugin to restart your Flutter application **With Native APIs**.

#### iOS Support
Unfortunately, there is no efficient way to restart a Flutter application using native APIs in iOS. However, you can look at [this StackOverflow answer](https://stackoverflow.com/a/66206070/9885611 "this StackOverflow answer"), or if you have a solution, do not hesitate to add it to [the open issue](https://github.com/gabrimatic/restart_app/issues/1 "the open issue").


## How to use it?
**1.  Add the package to pubspec.yaml dependency:**

```yaml
dependencies:
  restart_app: ^1.1.3
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

## Developer
By [Hossein Yousefpour](https://gabrimatic.info "Hossein Yousefpour")
🔗 [pub.dev repo](https://pub.dev/packages/restart_app "pub.dev")

&copy; All rights reserved.

## Donate
<a href="https://www.buymeacoffee.com/gabrimatic" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Book" style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;-webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;" ></a>
