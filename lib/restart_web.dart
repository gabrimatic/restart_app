import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart' as web show window;

/// Web implementation for the `restart` platform channel.
class RestartWeb {
  /// Registers the web plugin.
  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
      'restart',
      const StandardMethodCodec(),
      registrar,
    );

    final pluginInstance = RestartWeb();
    channel.setMethodCallHandler(pluginInstance.handleMethodCall);
  }

  /// Handles platform-channel calls from the Dart API.
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

  /// Reloads or replaces the current browser location.
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
