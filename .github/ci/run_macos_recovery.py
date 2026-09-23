#!/usr/bin/env python3
"""Prove real NSWorkspace launch failure and recovery in an owned app copy."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import traceback
import uuid

from run_desktop_proof import find_proof_processes, proof_process, wait_for_only_final_process


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def fingerprint(path: Path) -> dict:
    info = path.stat()
    require(path.is_file() and not path.is_symlink(), f'Expected regular executable: {path}')
    return dict(sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                size=info.st_size, mode=stat.S_IMODE(info.st_mode))


def restore_executable(executable: Path, backup: Path, original: dict) -> dict:
    """Restore only this run's verified backup, including after a failed probe."""
    if backup.exists():
        require(fingerprint(backup) == original, 'The owned executable backup changed.')
        require(not executable.exists(), 'Refusing to overwrite an unexpected executable.')
        backup.rename(executable)
    restored = fingerprint(executable)
    require(restored == original, 'Restored executable bytes or mode differ.')
    return restored


def one_event(boot: dict, kind: str, command_id: str | None = None) -> dict | None:
    matches = [event for event in boot['events'] if event['kind'] == kind and
               (command_id is None or event.get('commandId') == command_id)]
    require(len(matches) <= 1, f'Duplicate {kind} event in {boot["bootId"]}')
    return matches[0] if matches else None


def validate_recovery(report: dict) -> None:
    boots = report['boots']
    require(len(boots) == 2, 'Expected exactly two Dart boots.')
    initial, replacement = sorted(boots, key=lambda boot: boot['events'][0]['timestampMicros'])
    require(initial['pid'] != replacement['pid'] and initial['bootId'] != replacement['bootId'],
            'Retry did not start a fresh native process and Dart boot.')
    require(initial['pid'] == report['initial_pid'], 'Initial Popen PID differs from Dart evidence.')
    for boot in boots:
        require(boot['runId'] == report['run_id'], 'Stale boot run ID.')
        require(Path(boot['executable']).resolve() == Path(report['executable']).resolve(),
                'Dart boot resolved another executable.')
        require(Path(boot['bundle']).resolve() == Path(report['copied_bundle']).resolve(),
                'Dart boot resolved another application bundle.')
        require(boot['events'] and all(
            event['runId'] == report['run_id'] and event['bootId'] == boot['bootId'] and
            event['pid'] == boot['pid'] and event['timestampMicros'] >= report['started_micros']
            for event in boot['events']), 'Invalid or stale per-boot event identity.')
        ready = one_event(boot, 'ready')
        require(ready is not None and ready['memory'] == 0, 'Fresh Dart memory was not proven.')
        require(ready['capability']['fullProcessRestart'] is True and
                ready['capability']['platformDefaultMode'] == 'process',
                'Native channel unavailable on boot.')
    failure = one_event(initial, 'fail_result', report['commands']['fail'])
    require(failure is not None and failure['success'] is False and
            failure['code'] == 'RESTART_FAILED' and failure['mode'] == 'process' and
            bool(failure['message']), 'Missing structured native RESTART_FAILED result.')
    failure_started = one_event(initial, 'fail_started', report['commands']['fail'])
    retry_started = one_event(initial, 'retry_started', report['commands']['retry'])
    require(failure_started is not None and retry_started is not None and
            report['executable_removed_micros'] < failure_started['timestampMicros'] <=
            failure['timestampMicros'] < report['restored_micros'] <
            retry_started['timestampMicros'], 'Failure and restore commands were not ordered.')
    alive = one_event(initial, 'failure_channel_alive', report['commands']['fail'])
    ping = one_event(initial, 'ping', report['commands']['old_ping'])
    for event in (alive, ping):
        require(event is not None and event['memory'] == 4321 and
                event['capability']['fullProcessRestart'] is True and
                event['timestampMicros'] >= failure['timestampMicros'],
                'Old native channel or Dart memory did not survive failure.')
    retry = one_event(initial, 'retry_result', report['commands']['retry'])
    require(retry is not None and retry['success'] is True and retry['mode'] == 'process' and
            retry['code'] is None, 'Retry was not accepted after the native error.')
    final_ping = one_event(replacement, 'ping', report['commands']['new_ping'])
    require(final_ping is not None and final_ping['memory'] == 0 and
            final_ping['capability']['fullProcessRestart'] is True,
            'Replacement app was not live with reset Dart memory.')
    require(report['failure_window']['executable_absent'] is True and
            report['failure_window']['initial_process_alive'] is True and
            report['failure_window']['boot_count'] == 1,
            'Failure was not observed while the executable was absent and old app alive.')
    require(report['restored_fingerprint'] == report['original_fingerprint'] and
            one_event(replacement, 'ready')['timestampMicros'] >= retry_started['timestampMicros'],
            'Executable was not restored identically before retry.')
    require(report['old_process_exit_code'] is not None and
            report['live_processes_before_cleanup'] == [replacement['pid']],
            'The old process survived or an extra app instance remains.')


def run_probe(bundle: Path, output: Path, provenance: Path | None = None) -> dict:
    require(sys.platform == 'darwin', 'This proof requires macOS.')
    require(not output.exists(), f'Refusing to replace existing proof: {output}')
    bundle = bundle.resolve()
    require(bundle.suffix == '.app' and bundle.is_dir(), 'Pass the built QA .app.')
    with (bundle / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    name = info['CFBundleExecutable']
    require(isinstance(name, str) and Path(name).name == name, 'Unsafe bundle executable name.')
    require('restartMacosRecovery' in info['CFBundleIdentifier'],
            'Use the distinct generated restart_macos_recovery QA consumer.')
    run_id = uuid.uuid4().hex
    owned = Path(tempfile.mkdtemp(prefix='restart_app_macos_recovery_')).resolve()
    copied = owned / f'restart_macos_recovery_{run_id}.app'
    shutil.copytree(bundle, copied, symlinks=True)
    executable = copied / 'Contents/MacOS' / name
    backup = executable.with_name(f'{name}.recovery-backup-{run_id}')
    original = fingerprint(executable)
    directories = [Path.home() / 'Library/Containers' / info['CFBundleIdentifier'] /
                   'Data/restart_app_macos_recovery' / run_id,
                   Path.home() / 'restart_app_macos_recovery' / run_id]
    require(not any(path.exists() for path in directories), 'Run directory already exists.')
    require(not find_proof_processes(executable), 'The unique copied app is already running.')
    report = dict(complete=False, run_id=run_id, platform='macos',
                  started_micros=time.time_ns() // 1000, source_bundle=str(bundle),
                  copied_bundle=str(copied), bundle_identifier=info['CFBundleIdentifier'],
                  executable=str(executable), backup=str(backup),
                  original_fingerprint=original, commands={}, controller_events=[], boots=[])
    if provenance is not None:
        report['build_provenance_path'] = str(provenance.resolve())
        report['build_provenance'] = json.loads(provenance.read_text())
    output.parent.mkdir(parents=True, exist_ok=True)
    log_file = output.with_suffix('.log')
    process = None
    directory = None
    known_pids = set()

    def save() -> None:
        output.write_text(json.dumps(report, indent=2) + '\n')

    def read_boots() -> list[dict]:
        nonlocal directory
        found = [path for path in directories if path.exists()]
        require(len(found) <= 1, 'Probe wrote to multiple HOME locations.')
        if found:
            directory = found[0]
            report['evidence_directory'] = str(directory)
        boots = [] if directory is None else [json.loads(path.read_text())
                                              for path in sorted(directory.glob('boot-*.json'))]
        report['boots'] = boots
        for boot in boots:
            require(boot['runId'] == run_id and Path(boot['executable']).resolve() == executable,
                    'Foreign boot evidence in the owned run directory.')
            require(isinstance(boot['pid'], int) and boot['pid'] > 0, 'Invalid boot PID.')
            known_pids.add(boot['pid'])
            fatal = one_event(boot, 'fatal')
            require(fatal is None, f'Probe reported fatal error: {fatal}')
        return boots

    def wait(description, predicate, timeout=45):
        deadline = time.monotonic() + timeout
        while True:
            value = predicate(read_boots())
            if value:
                report['controller_events'].append(dict(kind=description,
                    timestampMicros=time.time_ns() // 1000))
                save()
                return value
            if time.monotonic() >= deadline:
                raise TimeoutError(f'Timed out waiting for {description}')
            time.sleep(0.1)

    def send(boot: dict, action: str, key: str) -> str:
        require(directory is not None, 'App readiness was not established.')
        command_id = uuid.uuid4().hex
        report['commands'][key] = command_id
        command = dict(runId=run_id, bootId=boot['bootId'], action=action, id=command_id)
        temporary = directory / 'command.json.tmp'
        temporary.write_text(json.dumps(command))
        temporary.replace(directory / 'command.json')
        return command_id

    def wait_event(boot: dict, kind: str, command_id: str):
        return wait(kind, lambda boots: next((one_event(item, kind, command_id)
                    for item in boots if item['bootId'] == boot['bootId']), None))

    with log_file.open('w') as log:
        try:
            process = subprocess.Popen([str(executable)], stdout=log, stderr=subprocess.STDOUT)
            report['initial_pid'] = process.pid
            known_pids.add(process.pid)
            initial = wait('initial_ready', lambda boots: next(
                (boot for boot in boots if one_event(boot, 'ready')), None))
            require(initial['pid'] == process.pid, 'Initial boot did not match the owned child.')
            require(len(read_boots()) == 1, 'Unexpected pre-failure app instance.')
            executable.rename(backup)
            report['executable_removed_micros'] = time.time_ns() // 1000
            require(not executable.exists() and fingerprint(backup) == original,
                    'Could not make the copied executable unavailable.')
            failure_id = send(initial, 'fail', 'fail')
            failure = wait_event(initial, 'fail_result', failure_id)
            require(failure['success'] is False and failure['code'] == 'RESTART_FAILED' and
                    failure['mode'] == 'process' and bool(failure['message']),
                    f'Expected structured native launch failure, got {failure}')
            wait_event(initial, 'failure_channel_alive', failure_id)
            ping_id = send(initial, 'ping', 'old_ping')
            wait_event(initial, 'ping', ping_id)
            report['failure_window'] = dict(executable_absent=not executable.exists(),
                initial_process_alive=process.poll() is None, boot_count=len(read_boots()))
            require(all((report['failure_window']['executable_absent'],
                         report['failure_window']['initial_process_alive'],
                         report['failure_window']['boot_count'] == 1)),
                    'The old application did not remain alone and alive during launch failure.')
            report['restored_fingerprint'] = restore_executable(executable, backup, original)
            report['restored_micros'] = time.time_ns() // 1000
            save()
            retry_id = send(initial, 'retry', 'retry')
            wait_event(initial, 'retry_result', retry_id)
            replacement = wait('replacement_ready', lambda boots: next(
                (boot for boot in boots if boot['bootId'] != initial['bootId'] and
                 one_event(boot, 'ready')), None))
            ping_id = send(replacement, 'ping', 'new_ping')
            wait_event(replacement, 'ping', ping_id)
            report['old_process_exit_code'] = process.wait(timeout=10)
            report['live_processes_before_cleanup'] = wait_for_only_final_process(
                executable, replacement['pid'], timeout=10)
            read_boots()
            validate_recovery(report)
            report['complete'] = True
        except Exception as error:
            report['complete'] = False
            report['error'] = str(error)
            report['traceback'] = traceback.format_exc()
        finally:
            try:
                report['finally_restored_fingerprint'] = restore_executable(executable, backup, original)
            except Exception as error:
                report['complete'] = False
                report['restore_error'] = str(error)
            try:
                read_boots()
            except Exception as error:
                report['complete'] = False
                report['evidence_error'] = str(error)
            for pid in known_pids:
                # Backup identity is allowed only for this owned rename. Restore normally
                # means all PIDs resolve to the original copied executable again.
                if not proof_process(pid, executable, terminate=True):
                    proof_process(pid, backup, terminate=True)
            if process is not None:
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    report['complete'] = False
                    report['cleanup_error'] = 'The original owned process did not exit.'
            deadline = time.monotonic() + 5
            while True:
                live = find_proof_processes(executable) | find_proof_processes(backup)
                if not live or time.monotonic() >= deadline:
                    break
                time.sleep(0.1)
            report['owned_processes_after_cleanup'] = sorted(live & known_pids)
            report['unrecorded_processes_after_cleanup'] = sorted(live - known_pids)
            if live:
                report['complete'] = False
                report['cleanup_error'] = f'Disposable processes remain: {sorted(live)}'
            report['native_log'] = log_file.read_text(errors='replace')
            save()
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--build-provenance', type=Path)
    args = parser.parse_args()
    report = run_probe(args.bundle, args.output.resolve(), args.build_provenance)
    print(json.dumps(dict(complete=report['complete'], run_id=report['run_id'],
                         output=str(args.output), error=report.get('error')), indent=2))
    if not report['complete']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
