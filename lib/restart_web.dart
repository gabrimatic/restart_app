import 'dart:async';
// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html show window;

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// A web implementation of the Restart plugin.
class RestartWeb {
  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
      'restart',
      const StandardMethodCodec(),
      registrar,
    );

    final pluginInstance = RestartWeb();
    channel.setMethodCallHandler(pluginInstance.handleMethodCall);
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'restartApp':
        return restart(call.arguments as String?);
      default:
        return 'false';
    }
  }

  /// If the [webOrigin] == null, then it uses the [window.origin] to get the site origin.
  /// Fill [webOrigin] only when your current origin is different than the app's origin.
  void restart(String? webOrigin) {
    html.window.location.replace(
      webOrigin ?? html.window.origin.toString(),
    );
  }
}
