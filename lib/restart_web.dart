import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart' as web show window;

/// `RestartWeb` provides a web implementation of the `Restart` plugin.
///
/// It registers a `MethodChannel` named 'restart' for communication between the Flutter code
/// and the platform-specific web code.
///
/// The main functionality is provided by the `restart` method.
class RestartWeb {
  /// Registers this plugin with the given `registrar`.
  ///
  /// This creates a `MethodChannel` named 'restart', and sets the method call handler to
  /// this plugin's `handleMethodCall` method.
  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
      'restart',
      const StandardMethodCodec(),
      registrar,
    );

    final pluginInstance = RestartWeb();
    channel.setMethodCallHandler(pluginInstance.handleMethodCall);
  }

  /// Handles method calls from the Flutter code.
  ///
  /// If the method call is 'restartApp', it calls the `restart` method with the given `webOrigin`.
  /// Otherwise, throws a [PlatformException] for unrecognized method calls.
  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'restartCapability':
        return <String, Object?>{
          'fullProcessRestart': false,
          'flutterEngineRestart': false,
          'notificationFallback': false,
          'engineRestartConfigured': false,
          'platformDefaultMode': 'platformDefault',
          'reason': 'Web restart reloads the current page.',
        };
      case 'restartApp':
        final args = call.arguments as Map?;
        final mode = args?['mode'] as String? ?? 'platformDefault';
        if (mode != 'platformDefault') {
          throw PlatformException(
            code: 'UNSUPPORTED_RESTART_MODE',
            message: "Restart mode '$mode' is not supported on web.",
          );
        }

        final webOrigin = args?['webOrigin'] as String?;
        restart(webOrigin);
        if (args?['structuredResult'] == true) {
          return <String, Object?>{
            'success': true,
            'mode': 'platformDefault',
          };
        }
        return 'ok';
      default:
        throw PlatformException(
          code: 'Unimplemented',
          message: '${call.method} is not implemented on the web platform.',
        );
    }
  }

  /// Restarts the web app.
  ///
  /// The `webOrigin` parameter is optional. If it's null, the method uses the `window.origin`
  /// to get the site origin. This parameter should only be filled when your current origin
  /// is different than the app's origin. It defaults to null.
  ///
  /// This method replaces the current location with the given `webOrigin` (or `window.origin` if
  /// `webOrigin` is null), effectively reloading the web app.
  String restart(String? webOrigin) {
    try {
      final origin =
          (webOrigin != null && webOrigin.isNotEmpty) ? webOrigin : null;
      if (origin != null && origin.startsWith('#')) {
        web.window.location.hash = origin;
        web.window.location.reload();
      } else if (origin != null) {
        web.window.location.replace(origin);
      } else {
        // window.origin returns the literal string "null" in sandboxed iframes,
        // so we avoid passing it to replace() and fall back to a simple reload.
        final windowOrigin = web.window.origin.toString();
        if (windowOrigin.isNotEmpty && windowOrigin != 'null') {
          web.window.location.replace(windowOrigin);
        } else {
          web.window.location.reload();
        }
      }
      return 'ok';
    } catch (e) {
      throw PlatformException(
        code: 'RESTART_FAILED',
        message: 'Failed to reload the page: $e',
      );
    }
  }
}
