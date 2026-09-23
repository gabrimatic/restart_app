// Controlled Android stress consumer. The external runner exercises lifecycle
// transitions between native restarts and checks both UI and private artifacts.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:restart_app/restart_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _boot = DateTime.now().microsecondsSinceEpoch.toString();
int _dirty = 0;
int _cycle = 0;
String? _directory;
String? _runId;

class _LifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _event('lifecycle', {'state': state.name});
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.addObserver(_LifecycleObserver());
  try {
    await _probe();
  } catch (error, stack) {
    _show('FAIL $error');
    if (_directory != null) {
      _write(
          'failure', {'runId': _runId, 'error': '$error', 'stack': '$stack'});
    }
  }
}

void _show(String text) {
  debugPrint(text);
  runApp(MaterialApp(home: Scaffold(body: SafeArea(child: Text(text)))));
}

void _write(String name, Map<String, Object?> value) {
  final temporary = File('$_directory/restart-proof-$name-$_boot.tmp');
  temporary.writeAsStringSync(jsonEncode(value), flush: true);
  temporary.renameSync('$_directory/restart-proof-$name.json');
}

void _event(String event, Map<String, Object?> details) {
  if (_directory == null) return;
  File('$_directory/restart-proof-dart.jsonl').writeAsStringSync(
    '${jsonEncode({
          'event': event,
          'runId': _runId,
          'cycle': _cycle,
          'boot': _boot,
          'pid': pid,
          'time': DateTime.now().millisecondsSinceEpoch,
          ...details,
        })}\n',
    mode: FileMode.append,
    flush: true,
  );
}

void _saved(bool saved) {
  if (!saved) throw StateError('Could not persist proof state');
}

Future<void> _probe() async {
  final host = await const MethodChannel('restart_proof_host')
      .invokeMapMethod<String, dynamic>('host');
  if (host == null || host['filesDirectory'] is! String) {
    throw StateError('Missing disposable native host');
  }
  _directory = host['filesDirectory'] as String;
  final config = jsonDecode(
      File('$_directory/restart-proof-config.json').readAsStringSync()) as Map;
  _runId = config['runId'] as String;
  final requestedCycles = config['cycles'] as int;
  if (_runId!.isEmpty || requestedCycles < 1 || requestedCycles > 1000) {
    throw StateError('Invalid externally requested proof run');
  }
  final prefs = await SharedPreferences.getInstance();
  _cycle = prefs.getInt('cycle') ?? 0;
  final history = prefs.getStringList('history') ?? [];
  final requests = prefs.getStringList('requests') ?? [];
  final expectedRestart = prefs.getBool('restartPending') ?? false;
  if (_cycle > requestedCycles || _dirty != 0) {
    throw StateError('Invalid cycle or retained Dart state');
  }
  if (expectedRestart) {
    if (requests.length != _cycle || history.length != _cycle) {
      throw StateError(
          'Restart acceptance/concurrency evidence did not persist');
    }
    final previous = jsonDecode(history.last) as Map;
    final request = jsonDecode(requests.last) as Map;
    if (previous['boot'] == _boot ||
        (request['kind'] != 'platformDefault' && previous['pid'] == pid)) {
      throw StateError(
          'Native restart did not replace the required Dart/process state');
    }
  }
  final initial = _cycle == 0 && history.isEmpty;
  final kind = initial || expectedRestart ? 'restart' : 'rotation';
  if (initial || expectedRestart) {
    history.add(jsonEncode({
      'cycle': _cycle,
      'boot': _boot,
      'pid': pid,
      'dirty': _dirty,
      'activity': host['activity'],
    }));
    _saved(await prefs.setStringList('history', history));
    _saved(await prefs.setBool('restartPending', false));
  } else if (history.length != _cycle + 1 || requests.length != _cycle) {
    throw StateError(
        'Lifecycle recreation changed the persisted restart counter');
  }
  _event('boot', {
    'kind': kind,
    'activity': host['activity'],
    'orientation': host['orientation'],
    'dirty': _dirty
  });
  _event('lifecycle', {
    'state': WidgetsBinding.instance.lifecycleState?.name ?? 'unknown',
  });
  _show('READY run=$_runId cycle=$_cycle boot=$_boot pid=$pid '
      'activity=${host['activity']} orientation=${host['orientation']}');
  await WidgetsBinding.instance.endOfFrame;
  _write('ready', {
    'runId': _runId,
    'cycle': _cycle,
    'boot': _boot,
    'pid': pid,
    'activity': host['activity'],
    'orientation': host['orientation'],
    'kind': kind,
    'dirty': _dirty,
  });
  while (true) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final file = File('$_directory/restart-proof-command.json');
    if (!file.existsSync()) continue;
    final command = jsonDecode(file.readAsStringSync()) as Map;
    if (command['runId'] != _runId ||
        command['cycle'] != _cycle ||
        command['boot'] != _boot) continue;
    if (command['action'] == 'complete' && _cycle == requestedCycles) {
      _write('summary', {
        'runId': _runId,
        'requestedCycles': requestedCycles,
        'complete': true,
        'finalBoot': _boot,
        'finalPid': pid,
        'history': history.map((value) => jsonDecode(value)).toList(),
        'requests': requests.map((value) => jsonDecode(value)).toList(),
      });
      _show('PASS $requestedCycles Android restarts run=$_runId '
          'cycle=$_cycle boot=$_boot pid=$pid');
      return;
    }
    if (command['action'] != 'restart' || _cycle >= requestedCycles) {
      throw StateError('Unexpected external command: $command');
    }
    break;
  }

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
  final requestKind = ['platformDefault', 'process', 'forceKill'][_cycle % 3];
  final mode = requestKind == 'process'
      ? RestartMode.process
      : RestartMode.platformDefault;
  final forceKill = requestKind == 'forceKill';
  _saved(await prefs.setInt('cycle', _cycle + 1));
  _saved(await prefs.setBool('restartPending', true));
  _dirty = 137;
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
  if (!result.success ||
      result.mode !=
          (requestKind == 'platformDefault'
              ? RestartMode.platformDefault
              : RestartMode.process)) {
    throw StateError('${result.code}: ${result.message}');
  }
  await Future.wait(duplicates);
  requests.add(jsonEncode({
    'cycle': _cycle,
    'kind': requestKind,
    'mode': mode.name,
    'forceKill': forceKill,
    'resolvedMode': result.mode.name,
    'duplicatesRejected': duplicates.length,
    'unsupportedRejected': 2,
  }));
  _saved(await prefs.setStringList('requests', requests));
  Timer(const Duration(seconds: 20), () {
    _show('FAIL accepted restart did not complete');
    _write('failure', {
      'runId': _runId,
      'error': 'Accepted restart did not complete within 20 seconds'
    });
  });
}
