import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:restart_app/restart_app.dart';

final _status = ValueNotifier<String>('Preparing macOS recovery proof');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(
    home: Scaffold(
      body: Center(
        child: ValueListenableBuilder<String>(
          valueListenable: _status,
          builder: (context, value, child) => Text(value),
        ),
      ),
    ),
  ));
  unawaited(_run());
}

Future<void> _run() async {
  _Probe? probe;
  try {
    if (!Platform.isMacOS) throw StateError('This probe requires macOS.');
    final executable = File(Platform.resolvedExecutable);
    final bundle = executable.parent.parent.parent;
    final name = bundle.uri.pathSegments.where((part) => part.isNotEmpty).last;
    final match = RegExp(r'^restart_macos_recovery_([0-9a-f]{32})\.app$')
        .firstMatch(name);
    if (match == null) throw StateError('Launch the run-specific app copy.');
    final runId = match.group(1)!;
    final directory = Directory(
      '${Platform.environment['HOME']}/restart_app_macos_recovery/$runId',
    )..createSync(recursive: true);
    probe = _Probe(runId, directory, executable.path, bundle.path);
    await probe.run();
  } on Object catch (error, stack) {
    _status.value = 'FAILED: $error';
    probe?.record(
        'fatal', {'error': error.toString(), 'stack': stack.toString()});
    stderr.writeln('$error\n$stack');
  }
}

class _Probe {
  _Probe(this.runId, this.directory, this.executable, this.bundle);

  final String runId;
  final Directory directory;
  final String executable;
  final String bundle;
  final String bootId = '${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid';
  final List<Map<String, Object?>> events = [];
  final Set<String> commands = {};
  int memory = 0;

  void record(String kind, [Map<String, Object?> values = const {}]) {
    events.add({
      'kind': kind,
      'runId': runId,
      'bootId': bootId,
      'pid': pid,
      'timestampMicros': DateTime.now().toUtc().microsecondsSinceEpoch,
      'memory': memory,
      ...values,
    });
    final path = '${directory.path}/boot-$bootId.json';
    File('$path.tmp')
      ..writeAsStringSync(
          jsonEncode({
            'runId': runId,
            'bootId': bootId,
            'pid': pid,
            'executable': executable,
            'bundle': bundle,
            'events': events,
          }),
          flush: true)
      ..renameSync(path);
    _status.value = '$kind\nrun=$runId\nboot=$bootId\npid=$pid';
  }

  Future<Map<String, Object?>> capability() async {
    final value = await Restart.restartCapability();
    if (!value.fullProcessRestart ||
        value.platformDefaultMode != RestartMode.process) {
      throw StateError('The native restart channel is unavailable.');
    }
    return {
      'fullProcessRestart': value.fullProcessRestart,
      'platformDefaultMode': value.platformDefaultMode.name,
      'reason': value.reason,
    };
  }

  Future<void> run() async {
    record('ready', {'capability': await capability()});
    final commandFile = File('${directory.path}/command.json');
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!commandFile.existsSync()) continue;
      final command = jsonDecode(commandFile.readAsStringSync()) as Map;
      if (command['runId'] != runId || command['bootId'] != bootId) continue;
      final commandId = command['id'] as String;
      if (!commands.add(commandId)) continue;
      final action = command['action'] as String;
      if (action == 'ping') {
        record(
            'ping', {'commandId': commandId, 'capability': await capability()});
        continue;
      }
      if (action != 'fail' && action != 'retry') {
        throw StateError('Unknown external command: $action');
      }
      if (action == 'fail') memory = 4321;
      record('${action}_started', {'commandId': commandId});
      final result = await Restart.restartApp(mode: RestartMode.process);
      record('${action}_result', {
        'commandId': commandId,
        'success': result.success,
        'mode': result.mode.name,
        'code': result.code,
        'message': result.message,
      });
      if (action == 'fail') {
        record('failure_channel_alive', {
          'commandId': commandId,
          'capability': await capability(),
        });
      }
    }
  }
}
