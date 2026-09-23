// Entrypoint for the CI restart-proof smoke app. CI copies this file into a
// freshly created Flutter desktop app that depends on restart_app, runs it,
// and verifies repeated native relaunches plus the resulting Dart state.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:restart_app/restart_app.dart';

final _restartModes = <RestartMode>[
  for (var cycle = 0; cycle < 5; cycle++) ...[
    RestartMode.platformDefault,
    RestartMode.process,
  ],
];

// This is deliberately in-memory state. A desktop process relaunch must
// initialize it back to zero while the file-backed launch counter survives.
int _volatileDartState = 0;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;
  final files = _ProofFiles(Directory('$home/restart_app_ci_proof'));
  _ProofState? state;

  try {
    await files.directory.create(recursive: true);
    state = _loadOrStartState(files);

    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'restart proof run=${state.runId} '
              'cycle=${state.cycle} pid=$pid',
            ),
          ),
        ),
      ),
    );

    await _runProof(files, state);
  } catch (error, stackTrace) {
    _writeFailure(files, state?.runId, error, stackTrace);
  }
}

Future<void> _runProof(_ProofFiles files, _ProofState state) async {
  final cycle = state.cycle;
  final startupVolatileState = _volatileDartState;

  if (state.persistedLaunches != cycle) {
    throw StateError(
      'Persisted launch count ${state.persistedLaunches} does not match '
      'cycle $cycle.',
    );
  }
  if (cycle > 0 && state.lastVolatileState == startupVolatileState) {
    throw StateError(
      'Dart state did not reset across relaunch: '
      '$startupVolatileState.',
    );
  }

  if (cycle > 0) {
    final sameProcess = state.lastPid == '$pid';
    if (sameProcess != Platform.isLinux) {
      throw StateError(
          'Unexpected PID after restart: previous=${state.lastPid} '
          'current=$pid platform=${Platform.operatingSystem}.');
    }
  }
  _appendResult(files, [
    'run_id=${state.runId}',
    'boot=$cycle',
    'pid=$pid',
    'startup_volatile=$startupVolatileState',
    'persisted_launches=${state.persistedLaunches}',
  ]);

  if (cycle == 0) {
    await Future<void>.delayed(const Duration(seconds: 1));
    final capability = await Restart.restartCapability();
    if (!capability.fullProcessRestart ||
        capability.platformDefaultMode != RestartMode.process) {
      throw StateError(
        'Unexpected desktop capability: '
        'fullProcessRestart=${capability.fullProcessRestart}, '
        'platformDefaultMode=${capability.platformDefaultMode.name}.',
      );
    }
    _appendResult(
      files,
      [
        'run_id=${state.runId}',
        'cycle=$cycle',
        'capability.fullProcessRestart=${capability.fullProcessRestart}',
        'capability.platformDefaultMode=${capability.platformDefaultMode.name}',
        'capability.reason=${capability.reason ?? ''}',
      ],
    );

    for (final mode in [
      RestartMode.flutterEngine,
      RestartMode.notificationFallback,
    ]) {
      final rejected = await Restart.restartApp(mode: mode);
      _appendResult(
        files,
        [
          'run_id=${state.runId}',
          'cycle=$cycle',
          'requested_mode=${mode.name}',
          'success=${rejected.success}',
          'mode=${rejected.mode.name}',
          'code=${rejected.code ?? ''}',
          'message=${rejected.message ?? ''}',
        ],
      );
      if (rejected.success || rejected.code != 'UNSUPPORTED_RESTART_MODE') {
        throw StateError(
          'Unsupported mode ${mode.name} was not rejected: '
          'success=${rejected.success}, code=${rejected.code}.',
        );
      }
    }
  }

  // Mutate only in-memory Dart state. The next process must observe zero
  // again, while persistedLaunches and lastVolatileState survive in the file.
  _volatileDartState = 1000 + cycle;
  state.lastVolatileState = _volatileDartState;
  state.persistedLaunches += 1;
  state.cycle += 1;
  state.lastPid = '$pid';
  state.write(files.stateFile);

  if (cycle < _restartModes.length) {
    // Give the desktop window and channel time to settle before each request.
    await Future<void>.delayed(const Duration(seconds: 1));
    final requestedMode = _restartModes[cycle];
    final result = await Restart.restartApp(mode: requestedMode);
    _appendResult(
      files,
      [
        'run_id=${state.runId}',
        'cycle=$cycle',
        'requested_mode=${requestedMode.name}',
        'success=${result.success}',
        'mode=${result.mode.name}',
        'code=${result.code ?? ''}',
        'message=${result.message ?? ''}',
      ],
    );
    if (!result.success || result.mode != RestartMode.process) {
      throw StateError(
        'Restart cycle $cycle failed: success=${result.success}, '
        'mode=${result.mode.name}, code=${result.code}.',
      );
    }
    // An accepted request is not proof of a relaunch. If this process keeps
    // running, leave a failure artifact for the external runner.
    Future<void>.delayed(const Duration(seconds: 10), () {
      _writeFailure(
          files,
          state.runId,
          StateError('Accepted restart did not relaunch within 10 seconds'),
          StackTrace.current);
    });
    return;
  }

  if (_volatileDartState != 1000 + cycle) {
    throw StateError('Unexpected in-memory state before final proof.');
  }
  state.complete = true;
  state.write(files.stateFile);
  files.proofFile.writeAsStringSync(
    [
      'RESTARTED_OK',
      'run_id=${state.runId}',
      'launches=${state.persistedLaunches}',
      'restarts=${_restartModes.length}',
      'state_reset=true',
      'state_persisted=true',
      'last_pid=${state.lastPid ?? ''}',
    ].join(' '),
    flush: true,
  );
}

_ProofState _loadOrStartState(_ProofFiles files) {
  final requestedRunId = _requestedRunId();
  final existing = _ProofState.read(files.stateFile);
  final canResume = existing != null &&
      !existing.complete &&
      (requestedRunId == null || requestedRunId == existing.runId);
  if (canResume) {
    files.runIdFile.writeAsStringSync(existing.runId, flush: true);
    return existing;
  }

  final runId = requestedRunId ?? _freshRunId();
  files.clearRunArtifacts();
  final state = _ProofState.initial(runId);
  state.write(files.stateFile);
  files.runIdFile.writeAsStringSync(runId, flush: true);
  return state;
}

String? _requestedRunId() {
  final value = Platform.environment['RESTART_APP_PROOF_RUN_ID']?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  return sanitized.isEmpty ? null : sanitized;
}

String _freshRunId() => '${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid';

void _appendResult(_ProofFiles files, List<String> lines) {
  files.resultFile.writeAsStringSync(
    '${lines.join('\n')}\n',
    mode: FileMode.append,
    flush: true,
  );
}

void _writeFailure(
  _ProofFiles files,
  String? runId,
  Object error,
  StackTrace stackTrace,
) {
  try {
    files.directory.createSync(recursive: true);
    files.failureFile.writeAsStringSync(
      [
        'RESTARTED_FAILED',
        'run_id=${runId ?? ''}',
        'error=$error',
        stackTrace.toString(),
      ].join('\n'),
      flush: true,
    );
  } on Object {
    // The proof runner reports the original failure when the artifact path is
    // unavailable. There is no second channel to report a file-write error.
  }
}

class _ProofFiles {
  _ProofFiles(this.directory);

  final Directory directory;

  File get stateFile => File('${directory.path}/state.json');
  File get runIdFile => File('${directory.path}/run_id.txt');
  File get resultFile => File('${directory.path}/restart_result.txt');
  File get proofFile => File('${directory.path}/restart_proof.txt');
  File get failureFile => File('${directory.path}/restart_failure.txt');

  void clearRunArtifacts() {
    for (final file in [runIdFile, resultFile, proofFile, failureFile]) {
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }
}

class _ProofState {
  _ProofState({
    required this.runId,
    required this.cycle,
    required this.persistedLaunches,
    required this.lastVolatileState,
    required this.lastPid,
    required this.complete,
  });

  factory _ProofState.initial(String runId) => _ProofState(
        runId: runId,
        cycle: 0,
        persistedLaunches: 0,
        lastVolatileState: null,
        lastPid: null,
        complete: false,
      );

  static _ProofState? read(File file) {
    if (!file.existsSync()) {
      return null;
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) {
        return null;
      }
      final runId = decoded['runId'];
      final cycle = decoded['cycle'];
      final persistedLaunches = decoded['persistedLaunches'];
      final lastVolatileState = decoded['lastVolatileState'];
      final lastPid = decoded['lastPid'];
      final complete = decoded['complete'];
      if (runId is! String ||
          runId.isEmpty ||
          cycle is! int ||
          cycle < 0 ||
          persistedLaunches is! int ||
          persistedLaunches < 0 ||
          (lastVolatileState != null && lastVolatileState is! int) ||
          (lastPid != null && lastPid is! String) ||
          complete is! bool) {
        return null;
      }
      return _ProofState(
        runId: runId,
        cycle: cycle,
        persistedLaunches: persistedLaunches,
        lastVolatileState: lastVolatileState as int?,
        lastPid: lastPid as String?,
        complete: complete,
      );
    } on Object {
      return null;
    }
  }

  final String runId;
  int cycle;
  int persistedLaunches;
  int? lastVolatileState;
  String? lastPid;
  bool complete;

  void write(File file) {
    file.writeAsStringSync(
      jsonEncode({
        'runId': runId,
        'cycle': cycle,
        'persistedLaunches': persistedLaunches,
        'lastVolatileState': lastVolatileState,
        'lastPid': lastPid,
        'complete': complete,
      }),
      flush: true,
    );
  }
}
