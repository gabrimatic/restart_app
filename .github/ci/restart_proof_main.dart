// Entrypoint for the CI restart-proof smoke app. CI copies this file into a
// freshly created Flutter desktop app that depends on restart_app, runs it,
// and verifies repeated native relaunches plus the resulting Dart state.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:restart_app/restart_app.dart';

// This is deliberately in-memory state. A desktop process relaunch must
// initialize it back to zero while the file-backed launch counter survives.
int _volatileDartState = 0;

Future<void> main(List<String> arguments) async {
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

    await _runProof(files, state, arguments);
  } catch (error, stackTrace) {
    _writeFailure(files, state?.runId, error, stackTrace);
  }
}

Future<void> _runProof(
  _ProofFiles files,
  _ProofState state,
  List<String> arguments,
) async {
  final cycle = state.cycle;
  final startupVolatileState = _volatileDartState;

  if (state.linuxFailureInFlight) {
    throw StateError('The Linux failure probe unexpectedly relaunched.');
  }
  if (Platform.isLinux || Platform.isWindows) {
    const expected = 'restart proof "quoted" café 東京';
    if (arguments.length != 1 || arguments.single != expected) {
      throw StateError('Original arguments changed on boot $cycle: $arguments');
    }
  }

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
    'arguments_preserved=${Platform.isLinux || Platform.isWindows}',
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

    if (Platform.isLinux) {
      await _verifyLinuxFailureRecovery(files, state);
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

  if (cycle < state.requestedCycles) {
    // Give the desktop window and channel time to settle before each request.
    await Future<void>.delayed(const Duration(seconds: 1));
    final requestedMode =
        cycle.isEven ? RestartMode.platformDefault : RestartMode.process;
    // Send separate native channel calls so a Dart-side guard cannot make this
    // pass while the native plugin still permits duplicate replacements.
    final requests = await Future.wait([
      _requestNativeRestart(requestedMode),
      _requestNativeRestart(requestedMode),
    ]);
    final result = requests.first;
    final duplicate = requests.last;
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
        'duplicate_code=${duplicate.code ?? ''}',
      ],
    );
    if (!result.success || result.mode != RestartMode.process) {
      throw StateError(
        'Restart cycle $cycle failed: success=${result.success}, '
        'mode=${result.mode.name}, code=${result.code}.',
      );
    }
    if (duplicate.success || duplicate.code != 'RESTART_ALREADY_IN_PROGRESS') {
      throw StateError('Concurrent native restart was not rejected: '
          'success=${duplicate.success}, code=${duplicate.code}.');
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
      'requested_restarts=${state.requestedCycles}',
      'restarts=${state.requestedCycles}',
      'state_reset=true',
      'state_persisted=true',
      'concurrent_requests_rejected=${state.requestedCycles}',
      if (Platform.isLinux || Platform.isWindows) 'arguments_preserved=true',
      if (Platform.isLinux) 'deferred_failure_recovered=true',
      'last_pid=${state.lastPid ?? ''}',
    ].join(' '),
    flush: true,
  );
}

Future<RestartResult> _requestNativeRestart(RestartMode mode) async {
  try {
    final result = await const MethodChannel('restart')
        .invokeMethod<dynamic>('restartApp', {
      'mode': mode.name,
      'structuredResult': true,
    });
    if (result is! Map) {
      throw StateError('Unexpected native result: $result');
    }
    return RestartResult.fromMap(result, fallbackMode: mode);
  } on PlatformException catch (error) {
    return RestartResult.error(error, mode);
  }
}

Future<void> _verifyLinuxFailureRecovery(
  _ProofFiles files,
  _ProofState state,
) async {
  final executable = Platform.resolvedExecutable;
  final permissions = Process.runSync('stat', ['-c', '%a', executable]);
  if (permissions.exitCode != 0) {
    throw StateError('Could not read disposable executable permissions.');
  }
  final originalMode = permissions.stdout.toString().trim();
  void chmod(String mode) {
    if (Process.runSync('chmod', [mode, executable]).exitCode != 0) {
      throw StateError('Could not change disposable executable permissions.');
    }
  }

  try {
    chmod('a-x');
    final rejected = await _requestNativeRestart(RestartMode.process);
    if (rejected.success || rejected.code != 'RESTART_FAILED') {
      throw StateError('An inaccessible executable passed native preflight.');
    }
  } finally {
    chmod(originalMode);
  }

  // Keep a complete backup, then replace only the disposable runner with an
  // executable file of an invalid format. access(X_OK) succeeds, so this must
  // reach a real execv failure rather than only the deferred access check.
  state.linuxFailureInFlight = true;
  state.write(files.stateFile);
  final backup = File('$executable.restart-proof-backup-${state.runId}');
  File(executable).copySync(backup.path);
  try {
    File(executable).deleteSync();
    File(executable)
        .writeAsStringSync('invalid executable format\n', flush: true);
    chmod(originalMode);
    final accepted = await _requestNativeRestart(RestartMode.process);
    if (!accepted.success) {
      throw StateError('Preflight failure retained the restart guard or the '
          'execv failure probe did not reach the deferred callback: '
          '${accepted.code}');
    }
    _volatileDartState = 808;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final capability = await Restart.restartCapability();
    if (_volatileDartState != 808 || !capability.fullProcessRestart) {
      throw StateError('execv failure did not preserve the old application.');
    }
  } finally {
    backup.renameSync(executable);
    chmod(originalMode);
  }
  state.linuxFailureInFlight = false;
  state.write(files.stateFile);
  _appendResult(files, [
    'run_id=${state.runId}',
    'linux_preflight_failure_recovered=true',
    'linux_exec_failure_preserved_app=true',
  ]);
  // The ordinary restart immediately following this probe must now succeed.
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
  final count = Platform.environment['RESTART_APP_PROOF_CYCLES'] ?? '30';
  final requestedCycles = int.tryParse(count);
  if (requestedCycles == null ||
      requestedCycles < 1 ||
      requestedCycles > 1000) {
    throw StateError('RESTART_APP_PROOF_CYCLES must be between 1 and 1000.');
  }
  final state = _ProofState.initial(runId, requestedCycles);
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
    required this.requestedCycles,
    required this.cycle,
    required this.persistedLaunches,
    required this.lastVolatileState,
    required this.lastPid,
    required this.complete,
    this.linuxFailureInFlight = false,
  });

  factory _ProofState.initial(String runId, int requestedCycles) => _ProofState(
        runId: runId,
        requestedCycles: requestedCycles,
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
      final requestedCycles = decoded['requestedCycles'];
      final cycle = decoded['cycle'];
      final persistedLaunches = decoded['persistedLaunches'];
      final lastVolatileState = decoded['lastVolatileState'];
      final lastPid = decoded['lastPid'];
      final complete = decoded['complete'];
      if (runId is! String ||
          runId.isEmpty ||
          requestedCycles is! int ||
          requestedCycles < 1 ||
          requestedCycles > 1000 ||
          cycle is! int ||
          cycle < 0 ||
          cycle > requestedCycles + 1 ||
          persistedLaunches is! int ||
          persistedLaunches < 0 ||
          (lastVolatileState != null && lastVolatileState is! int) ||
          (lastPid != null && lastPid is! String) ||
          complete is! bool) {
        return null;
      }
      return _ProofState(
        runId: runId,
        requestedCycles: requestedCycles,
        cycle: cycle,
        persistedLaunches: persistedLaunches,
        lastVolatileState: lastVolatileState as int?,
        lastPid: lastPid as String?,
        complete: complete,
        linuxFailureInFlight: decoded['linuxFailureInFlight'] == true,
      );
    } on Object {
      return null;
    }
  }

  final String runId;
  // NSWorkspace may drop the initial process environment on macOS. Keep the
  // externally requested count in durable state for every replacement boot.
  final int requestedCycles;
  int cycle;
  int persistedLaunches;
  int? lastVolatileState;
  String? lastPid;
  bool complete;
  bool linuxFailureInFlight;

  void write(File file) {
    file.writeAsStringSync(
      jsonEncode({
        'runId': runId,
        'requestedCycles': requestedCycles,
        'cycle': cycle,
        'persistedLaunches': persistedLaunches,
        'lastVolatileState': lastVolatileState,
        'lastPid': lastPid,
        'complete': complete,
        'linuxFailureInFlight': linuxFailureInFlight,
      }),
      flush: true,
    );
  }
}
