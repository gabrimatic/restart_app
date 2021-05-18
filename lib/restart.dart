import 'dart:async';

import 'package:flutter/services.dart';

class Restart {
  static const MethodChannel _channel = const MethodChannel('restart');

  static Future<bool> restartApp() async =>
      (await _channel.invokeMethod('restartApp')) == "ok";
}
