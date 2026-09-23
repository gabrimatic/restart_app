// Browser runtime probe. Build with:
// flutter build web -t lib/web_restart_probe.dart
// Serve with SPA fallback, then visit /probe?case=default&run=<unique-id>.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:restart_app/restart_app.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

final _boot = DateTime.now().microsecondsSinceEpoch.toString();
final _document = web.window.performance.timeOrigin.toString();
int _dirty = 0;
int _request = 0;

bool get _parentStorage => Uri.base.queryParameters['storage'] == 'parent';

Future<String?> _parentRequest(
  String operation,
  String key, [
  String? value,
]) async {
  final requestId = '$_boot-${++_request}';
  final result = Completer<String?>();
  final listener = ((web.Event event) {
    final message = event as web.MessageEvent;
    if (!identical(message.source, web.window.parent) ||
        !message.data.typeofEquals('string')) {
      return;
    }
    final data = jsonDecode((message.data as JSString).toDart);
    if (data is Map &&
        data['type'] == 'restart-probe-response' &&
        data['requestId'] == requestId &&
        !result.isCompleted) {
      result.complete(data['value'] as String?);
    }
  }).toJS;
  web.window.addEventListener('message', listener);
  try {
    web.window.parent?.postMessage(
      jsonEncode({
        'type': 'restart-probe-request',
        'requestId': requestId,
        'operation': operation,
        'key': key,
        'value': value,
      }).toJS,
      '*'.toJS,
    );
    return await result.future.timeout(const Duration(seconds: 5));
  } finally {
    web.window.removeEventListener('message', listener);
  }
}

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
  if (_parentStorage) {
    web.window.parent?.postMessage(
      jsonEncode({'type': 'restart-probe-result', 'message': message}).toJS,
      '*'.toJS,
    );
  }
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
  final baseHref = current.queryParameters['base'];
  if (baseHref != null) {
    (web.document.querySelector('base')! as web.HTMLBaseElement).href =
        baseHref;
  }
  final run = current.queryParameters['run'];
  if (run == null || run.isEmpty) {
    _show(
      'Provide a unique run query parameter and case=default, empty, hash, '
      'full, full-query, full-hash, full-identical, full-remove-hash, '
      'full-empty-hash, relative, relative-hash, relative-identical, '
      'relative-remove-hash, relative-empty-hash, or unsupported.',
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

  final preferences = _parentStorage
      ? null
      : await SharedPreferences.getInstance();
  final key = 'restartProbe.$run.$scenario';
  final saved = _parentStorage
      ? await _parentRequest('read', key)
      : preferences!.getString(key);
  if (saved != null) {
    final previous = jsonDecode(saved) as Map<String, dynamic>;
    if (previous['boot'] == _boot ||
        previous['document'] == _document ||
        _dirty != 0) {
      throw StateError('Dart state was not recreated.');
    }
    if (previous['destination'] != current.toString()) {
      throw StateError('Wrong destination: $current');
    }
    _show(
      'PASS $scenario\nrun=$run\npreviousBoot=${previous['boot']}\n'
      'boot=$_boot\npreviousDocument=${previous['document']}\n'
      'document=$_document\ndirty=$_dirty\npersisted=true\nurl=$current',
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
    case 'full-hash':
      destination = current.replace(fragment: '/destination');
      origin = destination.toString();
    case 'full-query':
      destination = current.replace(
        queryParameters: {...current.queryParameters, 'destination': 'true'},
      );
      origin = destination.toString();
    case 'full-identical':
      destination = current;
      origin = destination.toString();
    case 'full-remove-hash':
      destination = current.removeFragment();
      origin = destination.toString();
    case 'full-empty-hash':
      destination = current.replace(fragment: '');
      origin = destination.toString();
    case 'relative':
      origin = 'relative-destination?${current.query}';
      destination = Uri.parse(web.document.baseURI).resolve(origin);
    case 'relative-hash':
      destination = current.replace(fragment: '/destination');
      origin = destination.toString().substring(current.origin.length);
    case 'relative-identical':
      destination = current;
      origin = destination.toString().substring(current.origin.length);
    case 'relative-remove-hash':
      destination = current.removeFragment();
      origin = destination.toString().substring(current.origin.length);
    case 'relative-empty-hash':
      destination = current.replace(fragment: '');
      origin = destination.toString().substring(current.origin.length);
    default:
      throw ArgumentError.value(scenario, 'case');
  }

  final state = jsonEncode({
    'boot': _boot,
    'document': _document,
    'destination': destination.toString(),
  });
  if (_parentStorage) {
    await _parentRequest('write', key, state);
  } else if (!await preferences!.setString(key, state)) {
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
