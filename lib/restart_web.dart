import 'dart:async';

// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html show window;

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

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
  /// Otherwise, it returns 'false' to signify that the method call was not recognized.
  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'restartApp':
        return restart(call.arguments as String?);
      default:
        return 'false';
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
  void restart(String? webOrigin) {
    html.window.location.replace(
      webOrigin ?? html.window.origin.toString(),
    );
  }
}
