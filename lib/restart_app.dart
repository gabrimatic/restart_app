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
  static const MethodChannel _channel = MethodChannel('restart');

  /// Restarts the Flutter application.
  ///
  /// The [webOrigin] parameter is optional and web-only. If null, the method
  /// uses `window.origin` to reload the page. Use this when your current origin
  /// differs from the app's origin. Supports hash URL strategy (e.g. `'#/home'`).
  ///
  /// The [notificationTitle] and [notificationBody] parameters are iOS-only.
  /// On iOS, the app terminates via `exit(0)` and a local notification is shown
  /// to let the user reopen it. These parameters customize that notification's
  /// content. Notification permission must be granted before calling this method
  /// on iOS. Note: Apple's App Store guidelines prohibit calling `exit()` in
  /// most circumstances; use this on iOS only when the tradeoff is acceptable
  /// for your use case.
  ///
  /// The [forceKill] parameter is Android-only. When true, the old process is
  /// fully terminated after the new activity starts, preventing stale native
  /// resource locks. Defaults to false.
  ///
  /// Returns true if the restart was initiated successfully.
  static Future<bool> restartApp({
    String? webOrigin,
    String? notificationTitle,
    String? notificationBody,
    bool forceKill = false,
  }) async {
    final Map<String, dynamic> args = {
      'webOrigin': webOrigin,
      'notificationTitle': notificationTitle,
      'notificationBody': notificationBody,
      'forceKill': forceKill,
    };
    try {
      final result = await _channel.invokeMethod<String>('restartApp', args);
      return result == 'ok';
    } on PlatformException {
      return false;
    }
  }
}
