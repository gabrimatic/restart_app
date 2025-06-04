import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
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
  /// The `notificationTitle` and `notificationBody` parameters are optional. They allow 
  /// customization of the notification message displayed on iOS when restarting the app. 
  /// If not provided, default messages will be used.
  ///
  /// The `delayBeforeRestart` parameter allows adding a delay in milliseconds before 
  /// the restart occurs. This can help with cleanup operations. Defaults to 0.
  ///
  /// The `forceKill` parameter determines if the app should be forcefully terminated 
  /// on Android (similar to older behavior). Defaults to false.
  ///
  /// This method communicates with the platform-specific code to perform the restart operation,
  /// and then checks the response. If the response is "ok", it returns true, signifying that
  /// the restart operation was successful. Otherwise, it returns false.
  static Future<bool> restartApp({
    String? webOrigin,
    String? notificationTitle,
    String? notificationBody,
    int delayBeforeRestart = 0,
    bool forceKill = false,
  }) async {
    // Ensure we're on the main isolate for proper initialization
    if (!kIsWeb && !_isMainIsolate()) {
      throw StateError(
        'restartApp() must be called from the main isolate. '
        'If calling from a background isolate, ensure '
        'BackgroundIsolateBinaryMessenger.ensureInitialized() '
        'has been called first.',
      );
    }

    // Handle unsupported platforms
    if (!kIsWeb && 
        !Platform.isAndroid && 
        !Platform.isIOS && 
        !Platform.isWindows) {
      throw UnsupportedError(
        'Platform ${Platform.operatingSystem} is not supported. '
        'Supported platforms: Android, iOS, Web, Windows',
      );
    }

    final Map<String, dynamic> args = {
      'webOrigin': webOrigin,
      'notificationTitle': notificationTitle,
      'notificationBody': notificationBody,
      'delayBeforeRestart': delayBeforeRestart,
      'forceKill': forceKill,
    };
    
    try {
      final result = await _channel.invokeMethod('restartApp', args);
      return result == "ok";
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('RestartApp PlatformException: ${e.message}');
      }
      rethrow;
    }
  }

  /// Checks if the current isolate is the main isolate
  static bool _isMainIsolate() {
    try {
      // This will throw if not on main isolate
      ServicesBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }
}
