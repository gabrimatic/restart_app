import 'package:flutter/services.dart';

/// Restart behavior requested by the caller.
enum RestartMode {
  /// Uses the best behavior available for the current platform.
  platformDefault,

  /// Recreates the Flutter engine in the same native process.
  ///
  /// This is the recommended iOS mode when the host app has configured engine
  /// restart. It is not a full process restart.
  flutterEngine,

  /// Requests a native process relaunch where the platform supports it.
  process,

  /// iOS-only legacy fallback that schedules a local notification, exits, and
  /// requires the user to tap the notification to reopen the app.
  notificationFallback,
}

/// Describes restart behavior available on the current platform.
class RestartCapability {
  /// Creates a restart capability description.
  const RestartCapability({
    required this.fullProcessRestart,
    required this.flutterEngineRestart,
    required this.notificationFallback,
    required this.engineRestartConfigured,
    required this.platformDefaultMode,
    this.reason,
  });

  /// Whether this platform can relaunch the app in a fresh native process.
  final bool fullProcessRestart;

  /// Whether this platform can recreate Flutter in the current native process.
  final bool flutterEngineRestart;

  /// Whether the iOS legacy notification fallback is available.
  final bool notificationFallback;

  /// Whether iOS Flutter engine restart has been configured by the host app.
  final bool engineRestartConfigured;

  /// The behavior used by [RestartMode.platformDefault].
  final RestartMode platformDefaultMode;

  /// Optional explanation when a capability is unavailable or limited.
  final String? reason;

  /// Creates [RestartCapability] from a platform channel response.
  factory RestartCapability.fromMap(Map<dynamic, dynamic> map) {
    return RestartCapability(
      fullProcessRestart: map['fullProcessRestart'] == true,
      flutterEngineRestart: map['flutterEngineRestart'] == true,
      notificationFallback: map['notificationFallback'] == true,
      engineRestartConfigured: map['engineRestartConfigured'] == true,
      platformDefaultMode: _parseRestartMode(map['platformDefaultMode']),
      reason: map['reason'] as String?,
    );
  }
}

/// Structured result returned by [Restart.restart].
class RestartResult {
  /// Creates a restart result.
  const RestartResult({
    required this.success,
    required this.mode,
    this.code,
    this.message,
  });

  /// Whether the platform accepted and initiated the requested restart.
  final bool success;

  /// The mode that was accepted by the platform.
  final RestartMode mode;

  /// Platform-specific error code, when [success] is false.
  final String? code;

  /// Platform-specific error message, when [success] is false.
  final String? message;

  /// Creates a successful result.
  factory RestartResult.ok(RestartMode mode) {
    return RestartResult(success: true, mode: mode);
  }

  /// Creates [RestartResult] from a platform channel response.
  factory RestartResult.fromMap(Map<dynamic, dynamic> map) {
    return RestartResult(
      success: map['success'] == true,
      mode: _parseRestartMode(map['mode']),
      code: map['code'] as String?,
      message: map['message'] as String?,
    );
  }

  /// Creates a failed result from a platform exception.
  factory RestartResult.error(PlatformException error, RestartMode mode) {
    return RestartResult(
      success: false,
      mode: mode,
      code: error.code,
      message: error.message,
    );
  }
}

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

  /// Returns the restart behavior available on the current platform.
  static Future<RestartCapability> restartCapability() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'restartCapability',
      );

      return RestartCapability.fromMap(result ?? const {});
    } on PlatformException catch (error) {
      return RestartCapability(
        fullProcessRestart: false,
        flutterEngineRestart: false,
        notificationFallback: false,
        engineRestartConfigured: false,
        platformDefaultMode: RestartMode.platformDefault,
        reason: error.message ?? error.code,
      );
    }
  }

  /// Restarts the Flutter application and returns a structured result.
  ///
  /// iOS does not provide a public API for automatic full process restart.
  /// When iOS Flutter engine restart is configured in the host app,
  /// [RestartMode.platformDefault] uses [RestartMode.flutterEngine]. Otherwise
  /// use [RestartMode.notificationFallback] only when the legacy notification
  /// workaround is acceptable for your app.
  static Future<RestartResult> restart({
    RestartMode mode = RestartMode.platformDefault,
    String? webOrigin,
    String? notificationTitle,
    String? notificationBody,
    bool forceKill = false,
    bool iosLegacyNotificationFallback = false,
  }) async {
    final args = _restartArgs(
      mode: mode,
      webOrigin: webOrigin,
      notificationTitle: notificationTitle,
      notificationBody: notificationBody,
      forceKill: forceKill,
      structuredResult: true,
      iosLegacyNotificationFallback: iosLegacyNotificationFallback,
    );

    try {
      final result = await _channel.invokeMethod<dynamic>('restartApp', args);

      if (result is Map) {
        return RestartResult.fromMap(result);
      }

      if (result == 'ok') {
        return RestartResult.ok(mode);
      }

      return RestartResult(
        success: false,
        mode: mode,
        code: 'UNKNOWN_RESULT',
        message: 'Unexpected restart result: $result',
      );
    } on PlatformException catch (error) {
      return RestartResult.error(error, mode);
    }
  }

  /// Restarts the Flutter application.
  ///
  /// The [webOrigin] parameter is optional and web-only. If null, the method
  /// uses `window.origin` to reload the page. Use this when your current origin
  /// differs from the app's origin. Supports hash URL strategy (e.g. `'#/home'`).
  ///
  /// The [notificationTitle] and [notificationBody] parameters customize the
  /// iOS legacy notification fallback. iOS does not provide a public API for
  /// automatic full process restart. Configure iOS Flutter engine restart in
  /// the host app for the recommended same-process engine restart behavior.
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
    RestartMode mode = RestartMode.platformDefault,
  }) async {
    final args = _restartArgs(
      mode: mode,
      webOrigin: webOrigin,
      notificationTitle: notificationTitle,
      notificationBody: notificationBody,
      forceKill: forceKill,
      structuredResult: false,
      iosLegacyNotificationFallback: true,
    );

    try {
      final result = await _channel.invokeMethod<dynamic>('restartApp', args);
      if (result is Map) {
        return result['success'] == true;
      }
      return result == 'ok';
    } on PlatformException {
      return false;
    }
  }

  static Map<String, dynamic> _restartArgs({
    required RestartMode mode,
    required String? webOrigin,
    required String? notificationTitle,
    required String? notificationBody,
    required bool forceKill,
    required bool structuredResult,
    required bool iosLegacyNotificationFallback,
  }) {
    return {
      'mode': mode.name,
      'webOrigin': webOrigin,
      'notificationTitle': notificationTitle,
      'notificationBody': notificationBody,
      'forceKill': forceKill,
      'structuredResult': structuredResult,
      'iosLegacyNotificationFallback': iosLegacyNotificationFallback,
    };
  }
}

RestartMode _parseRestartMode(Object? value) {
  if (value is String) {
    for (final mode in RestartMode.values) {
      if (mode.name == value) {
        return mode;
      }
    }
  }

  return RestartMode.platformDefault;
}
