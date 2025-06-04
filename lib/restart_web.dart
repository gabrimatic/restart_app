import 'dart:async';

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
  /// If the method call is 'restartApp', it calls the `restart` method with the arguments.
  /// Otherwise, it returns 'false' to signify that the method call was not recognized.
  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'restartApp':
        // Handle both old single string argument and new Map arguments
        Map<String, dynamic>? args;
        if (call.arguments is Map) {
          args = Map<String, dynamic>.from(call.arguments as Map);
        } else if (call.arguments is String) {
          // Backward compatibility for old single string argument
          args = {'webOrigin': call.arguments as String};
        } else {
          args = <String, dynamic>{};
        }
        return restart(args);
      default:
        return 'false';
    }
  }

  /// Restarts the web app.
  ///
  /// The `args` map can contain:
  /// - `webOrigin`: Custom origin URL (optional)
  /// - `delayBeforeRestart`: Delay in milliseconds before restart (optional)
  ///
  /// This method handles hash-based routing and properly constructs URLs.
  /// If webOrigin contains a hash fragment, it will be properly handled.
  ///
  /// This method replaces the current location with the given webOrigin or reloads 
  /// the current page, effectively restarting the web app.
  String restart(Map<String, dynamic> args) {
    try {
      final String? webOrigin = args['webOrigin'] as String?;
      final int delayBeforeRestart = (args['delayBeforeRestart'] as int?) ?? 0;
      
      void performRestart() {
        String targetUrl;
        
        if (webOrigin != null && webOrigin.isNotEmpty) {
          // Handle hash-based routing
          if (webOrigin.startsWith('#')) {
            // If it starts with #, append to current origin
            targetUrl = '${web.window.origin}/${webOrigin}';
          } else if (webOrigin.startsWith('/') && !webOrigin.startsWith('//#')) {
            // Handle relative path that should be hash-based
            final currentHref = web.window.location.href;
            if (currentHref.contains('/#/')) {
              targetUrl = '${web.window.origin}/#${webOrigin}';
            } else {
              targetUrl = '${web.window.origin}${webOrigin}';
            }
          } else {
            // Use as provided
            targetUrl = webOrigin;
          }
        } else {
          // Default to current origin
          targetUrl = web.window.origin;
        }
        
        web.window.location.replace(targetUrl);
      }
      
      if (delayBeforeRestart > 0) {
        Future.delayed(Duration(milliseconds: delayBeforeRestart), performRestart);
      } else {
        performRestart();
      }
      
      return 'ok';
    } catch (e) {
      return 'error: $e';
    }
  }
}
