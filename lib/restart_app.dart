import 'dart:async';

import 'package:flutter/services.dart';

/// `Restart` class provides a method to restart a Flutter application.
///
/// It uses the Flutter platform channels to communicate with the platform-specific code.
/// Specifically, it uses a `MethodChannel` named 'restart' for this communication.
///
/// The main functionality is provided by the `restartApp` method.
class Restart {
  /// A private constant `MethodChannel`. This channel is used to communicate with the
  /// platform-specific code to perform the restart operation.
  static const MethodChannel _channel = const MethodChannel('restart');

  /// Restarts the Flutter application.
  ///
  /// The `webOrigin` parameter is optional. If it's null, the method uses the `window.origin`
  /// to get the site origin. This parameter should only be filled when your current origin
  /// is different than the app's origin. It defaults to null.
  ///
  /// The `customMessage` parameter is optional. It allows customization of the notification
  /// message displayed on iOS when restarting the app. If not provided, a default message
  /// will be used.
  ///
  /// This method communicates with the platform-specific code to perform the restart operation,
  /// and then checks the response. If the response is "ok", it returns true, signifying that
  /// the restart operation was successful. Otherwise, it returns false.
  static Future<bool> restartApp({
    String? webOrigin,
    String? notificationTitle,
    String? notificationBody,
  }) async {
    final Map<String, dynamic> args = {
      'webOrigin': webOrigin,
      'notificationTitle': notificationTitle,
      'notificationBody': notificationBody,
    };
    return (await _channel.invokeMethod('restartApp', args)) == "ok";
  }
}
