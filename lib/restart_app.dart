import 'dart:async';

import 'package:flutter/services.dart';

class Restart {
  static const MethodChannel _channel = const MethodChannel('restart');

  /// If the [webOrigin] == null, then it uses the [window.origin] to get the site origin.
  /// Fill [webOrigin] only when your current origin is different than the app's origin.
  static Future<bool> restartApp({String? webOrigin}) async =>
      (await _channel.invokeMethod('restartApp', webOrigin)) == "ok";
}
