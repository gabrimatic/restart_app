// Browser runtime probe. Build with:
// flutter build web -t lib/web_restart_probe.dart
// Serve with SPA fallback, then visit /probe?case=default&run=<unique-id>.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:restart_app/restart_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _boot = DateTime.now().microsecondsSinceEpoch.toString();
int _dirty = 0;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized().ensureSemantics();
  try {
    await _runProbe();
  } catch (error) {
    _show('FAIL: $error');
  }
}

void _show(String message) {
  debugPrint(message);
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Colors.white,
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              message,
              style: const TextStyle(color: Colors.black, fontSize: 18),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _runProbe() async {
  final current = Uri.base;
  final scenario = current.queryParameters['case'] ?? 'default';
  final run = current.queryParameters['run'];
  if (run == null || run.isEmpty) {
    _show(
      'Provide a unique run query parameter and case=default, empty, hash, '
      'full, relative, or unsupported.',
    );
    return;
  }
  final capability = await Restart.restartCapability();
  if (capability.fullProcessRestart ||
      capability.flutterEngineRestart ||
      capability.notificationFallback) {
    throw StateError('Unexpected browser capability.');
  }
  if (scenario == 'unsupported') {
    for (final mode in [
      RestartMode.process,
      RestartMode.flutterEngine,
      RestartMode.notificationFallback,
    ]) {
      final result = await Restart.restartApp(mode: mode);
      if (result.success || result.code != 'UNSUPPORTED_RESTART_MODE') {
        throw StateError('Unsupported mode was accepted: $mode');
      }
    }
    _show('PASS unsupported modes\nrun=$run\nboot=$_boot\nurl=$current');
    return;
  }

  final preferences = await SharedPreferences.getInstance();
  final key = 'restartProbe.$run.$scenario';
  final saved = preferences.getString(key);
  if (saved != null) {
    final previous = jsonDecode(saved) as Map<String, dynamic>;
    if (previous['boot'] == _boot || _dirty != 0) {
      throw StateError('Dart state was not recreated.');
    }
    if (previous['destination'] != current.toString()) {
      throw StateError('Wrong destination: $current');
    }
    _show(
      'PASS $scenario\nrun=$run\npreviousBoot=${previous['boot']}\n'
      'boot=$_boot\ndirty=$_dirty\npersisted=true\nurl=$current',
    );
    return;
  }

  final String? origin;
  final Uri destination;
  switch (scenario) {
    case 'default':
      origin = null;
      destination = current;
    case 'empty':
      origin = '';
      destination = current;
    case 'hash':
      origin = '#/destination';
      destination = current.replace(fragment: '/destination');
    case 'full':
      destination = current.replace(path: '/full-destination');
      origin = destination.toString();
    case 'relative':
      origin = 'relative-destination?${current.query}';
      // The example's web/index.html declares <base href="/">.
      destination = current.resolve('/').resolve(origin);
    default:
      throw ArgumentError.value(scenario, 'case');
  }

  if (!await preferences.setString(
    key,
    jsonEncode({'boot': _boot, 'destination': destination.toString()}),
  )) {
    throw StateError('Could not persist the probe state.');
  }
  _dirty = 137;
  _show('Restarting $scenario\nrun=$run\nboot=$_boot\ndirty=$_dirty');
  await Future<void>.delayed(const Duration(seconds: 1));
  final result = await Restart.restartApp(webOrigin: origin);
  if (!result.success) {
    throw StateError('${result.code}: ${result.message}');
  }
  Timer(const Duration(seconds: 10), () {
    _show('FAIL: accepted restart did not replace the document.');
  });
}
