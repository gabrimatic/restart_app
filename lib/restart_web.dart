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
  /// The `webOrigin` parameter is optional and defaults to null, which reloads
  /// the current page and preserves the current route. Pass a hash path such
  /// as `#/home` to move to that hash route and reload, or a full URL to
  /// replace the current location entirely. Relative URLs resolve against the
  /// document's base URL, including any HTML `base` element.
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
        // Reload the current URL so the active route survives the restart.
        // This also works in sandboxed iframes, where window.origin is the
        // literal string "null" and cannot be passed to replace().
        web.window.location.reload();
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
