// Self-running Android consumer probe. Each launch verifies the preceding
// restart before requesting the next. Clear application data to start a new run.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:restart_app/restart_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _boot = DateTime.now().microsecondsSinceEpoch.toString();
int _dirty = 0;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _probe();
  } catch (error) {
    _show('FAIL $error');
  }
}

void _show(String text) {
  debugPrint(text);
  runApp(MaterialApp(home: Scaffold(body: SafeArea(child: Text(text)))));
}

Future<void> _probe() async {
  final prefs = await SharedPreferences.getInstance();
  final cycle = prefs.getInt('cycle') ?? 0;
  final previousBoot = prefs.getString('boot');
  final previousPid = prefs.getInt('pid');
  final history = prefs.getStringList('history') ?? [];
  if (cycle > 0 && prefs.getInt('concurrencyVerified') != cycle) {
    throw StateError('Concurrent restart requests were not safely rejected');
  }
  if (cycle > 0 && (previousBoot == _boot || _dirty != 0)) {
    throw StateError('Dart state survived restart');
  }
  if (cycle > 0 && (cycle - 1) % 4 >= 2 && previousPid == pid) {
    throw StateError('Process restart retained PID $pid');
  }
  history.add('cycle=$cycle boot=$_boot pid=$pid dirty=$_dirty');
  if (!await prefs.setStringList('history', history)) {
    throw StateError('Could not save probe history');
  }
  if (cycle == 15) {
    _show('PASS 15 Android restarts\n${history.join('\n')}');
    return;
  }
  if (cycle > 15) throw StateError('Unexpected cycle $cycle');
  final capability = await Restart.restartCapability();
  if (!capability.fullProcessRestart || capability.flutterEngineRestart) {
    throw StateError('Unexpected capability');
  }
  for (final unsupported in [
    RestartMode.flutterEngine,
    RestartMode.notificationFallback
  ]) {
    final result = await Restart.restartApp(mode: unsupported);
    if (result.success || result.code != 'UNSUPPORTED_RESTART_MODE') {
      throw StateError('Unsupported mode was accepted: $unsupported');
    }
  }
  if (!await prefs.setInt('cycle', cycle + 1) ||
      !await prefs.setString('boot', _boot) ||
      !await prefs.setInt('pid', pid)) {
    throw StateError('Could not save restart state');
  }
  _dirty = 137;
  // Two consecutive activity restarts prove that the process-wide guard is
  // released by the replacement activity, including without a process exit.
  final mode =
      cycle % 4 == 2 ? RestartMode.process : RestartMode.platformDefault;
  final forceKill = cycle % 4 == 3;
  _show('Restarting cycle=$cycle mode=${mode.name} forceKill=$forceKill\n'
      'boot=$_boot pid=$pid dirty=$_dirty\n${jsonEncode(history)}');
  await Future<void>.delayed(const Duration(seconds: 1));
  final accepted = Restart.restartApp(mode: mode, forceKill: forceKill);
  const channel = MethodChannel('restart');
  final duplicates = List.generate(8, (index) async {
    try {
      await channel.invokeMethod<dynamic>('restartApp', {
        'mode': index.isEven ? 'platformDefault' : 'process',
        'structuredResult': index.isEven,
      });
      throw StateError('Concurrent native restart $index was accepted');
    } on PlatformException catch (error) {
      if (error.code != 'RESTART_ALREADY_IN_PROGRESS') rethrow;
    }
  });
  final result = await accepted;
  if (!result.success) throw StateError('${result.code}: ${result.message}');
  await Future.wait(duplicates);
  if (!await prefs.setInt('concurrencyVerified', cycle + 1)) {
    throw StateError('Could not save concurrent restart verification');
  }
  Timer(const Duration(seconds: 20),
      () => _show('FAIL accepted restart did not complete'));
}
