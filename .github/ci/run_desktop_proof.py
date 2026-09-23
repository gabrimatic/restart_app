#!/usr/bin/env python3
"""Run the built desktop application and require fresh native restart evidence."""
from __future__ import annotations

import argparse
import ctypes
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import sys
import time
import uuid


def proof_process(pid: int, executable: Path, *, terminate: bool = False) -> bool:
    """Check live executable identity, optionally terminating that same process."""
    if sys.platform == 'win32':
        from ctypes import wintypes
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        kernel.OpenProcess.restype = wintypes.HANDLE
        kernel.QueryFullProcessImageNameW.argtypes = [
            wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR,
            ctypes.POINTER(wintypes.DWORD)]
        kernel.QueryFullProcessImageNameW.restype = wintypes.BOOL
        kernel.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
        kernel.TerminateProcess.restype = wintypes.BOOL
        kernel.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
        kernel.GetExitCodeProcess.restype = wintypes.BOOL
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        kernel.CloseHandle.restype = wintypes.BOOL
        handle = kernel.OpenProcess(0x1001 if terminate else 0x1000, False, pid)
        if not handle:
            return False
        try:
            name = ctypes.create_unicode_buffer(32768)
            size = wintypes.DWORD(len(name))
            exit_code = wintypes.DWORD()
            if (kernel.GetExitCodeProcess(handle, ctypes.byref(exit_code)) and
                    exit_code.value == 259 and
                    kernel.QueryFullProcessImageNameW(handle, 0, name, ctypes.byref(size))):
                matches = os.path.normcase(os.path.realpath(name.value)) == os.path.normcase(str(executable))
                if matches and terminate:
                    kernel.TerminateProcess(handle, 0)
                return matches
        finally:
            kernel.CloseHandle(handle)
        return False

    if sys.platform == 'linux':
        try:
            name = os.readlink(f'/proc/{pid}/exe')
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            return False
        name = name.removesuffix(' (deleted)')
    else:
        query = subprocess.run(['ps', '-ww', '-p', str(pid), '-o', 'comm='],
                               capture_output=True, text=True, check=False)
        name = query.stdout.strip()
    matches = bool(name) and Path(name).resolve() == executable
    if matches and terminate:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    return matches


def find_proof_processes(executable: Path) -> set[int]:
    """Enumerate the exact disposable image for a read-only process leak check."""
    if sys.platform == 'win32':
        from ctypes import wintypes
        api = ctypes.WinDLL('psapi', use_last_error=True)
        api.EnumProcesses.argtypes = [ctypes.POINTER(wintypes.DWORD), wintypes.DWORD,
                                     ctypes.POINTER(wintypes.DWORD)]
        api.EnumProcesses.restype = wintypes.BOOL
        capacity = 1024
        while True:
            pids = (wintypes.DWORD * capacity)()
            needed = wintypes.DWORD()
            if not api.EnumProcesses(pids, ctypes.sizeof(pids), ctypes.byref(needed)):
                raise OSError(ctypes.get_last_error(), 'Could not enumerate proof processes')
            if needed.value < ctypes.sizeof(pids):
                candidates = list(pids[:needed.value // ctypes.sizeof(wintypes.DWORD)])
                break
            capacity *= 2
    elif sys.platform == 'linux':
        candidates = [int(path.name) for path in Path('/proc').iterdir() if path.name.isdecimal()]
    else:
        listing = subprocess.run(['ps', '-axo', 'pid=,comm='], capture_output=True,
                                 text=True, check=True)
        candidates = []
        for line in listing.stdout.splitlines():
            fields = line.strip().split(maxsplit=1)
            if len(fields) == 2 and Path(fields[1]).resolve() == executable:
                candidates.append(int(fields[0]))
    return {pid for pid in candidates if proof_process(pid, executable)}


def wait_for_only_final_process(executable: Path, final_pid: int,
                                timeout: float = 5) -> list[int]:
    deadline = time.monotonic() + timeout
    while True:
        live = find_proof_processes(executable)
        if live == {final_pid}:
            return sorted(live)
        if time.monotonic() >= deadline:
            raise RuntimeError(f'Expected only final PID {final_pid}; live disposable processes: {sorted(live)}')
        time.sleep(0.25)


def validate_proof(*, run_id: str, cycles: int, platform: str, state: dict,
                   result: str, summary: str, native_log: str) -> dict:
    """Validate boot evidence independently of the app's success summary."""
    def values(key):
        return re.findall(rf'^{re.escape(key)}=(.*)$', result, re.MULTILINE)

    def require(condition, message):
        if not condition:
            raise RuntimeError(message)

    fields = dict(token.split('=', 1) for token in summary.split() if '=' in token)
    expected = dict(run_id=run_id, requested_restarts=str(cycles),
                    launches=str(cycles + 1), restarts=str(cycles), state_reset='true',
                    state_persisted='true', concurrent_requests_rejected=str(cycles))
    require(summary.startswith('RESTARTED_OK '), 'Missing successful proof summary.')
    require(all(fields.get(key) == value for key, value in expected.items()),
            f'Wrong summary fields: {fields}')
    expected_modes = ['platformDefault' if cycle % 2 == 0 else 'process'
                      for cycle in range(cycles)]
    require(values('requested_mode') == ['flutterEngine', 'notificationFallback'] + expected_modes,
            'Native restart modes did not alternate for every requested cycle.')
    require(values('boot') == [str(cycle) for cycle in range(cycles + 1)],
            'Missing or duplicated boot sequence.')
    require(values('persisted_launches') == [str(cycle) for cycle in range(cycles + 1)],
            'Persisted state did not survive every boot.')
    require(values('startup_volatile') == ['0'] * (cycles + 1),
            'Fresh Dart state was not verified on every boot.')
    require(values('success') == ['false', 'false'] + ['true'] * cycles,
            'Missing accepted native restarts or unsupported-mode failures.')
    require(values('code').count('UNSUPPORTED_RESTART_MODE') == 2,
            'Unsupported modes were not rejected.')
    require(values('mode') == ['flutterEngine', 'notificationFallback'] + ['process'] * cycles,
            'Restart results did not report the expected mode for every request.')
    require(values('duplicate_code') == ['RESTART_ALREADY_IN_PROGRESS'] * cycles,
            'Concurrent native requests were not rejected on every cycle.')
    pid_values = values('pid')
    require(len(pid_values) == cycles + 1 and all(value.isdecimal() and int(value) > 0 for value in pid_values),
            'Missing valid boot PIDs.')
    pids = [int(value) for value in pid_values]
    require(len(set(pids)) == (1 if platform == 'linux' else cycles + 1),
            'Unexpected process identity across native restarts.')
    expected_state = dict(runId=run_id, requestedCycles=cycles, complete=True,
                          cycle=cycles + 1, persistedLaunches=cycles + 1,
                          lastPid=str(pids[-1]), lastVolatileState=1000 + cycles)
    require(all(state.get(key) == value for key, value in expected_state.items()),
            f'Wrong final persisted state: {state}')
    require(fields.get('last_pid') == str(pids[-1]), 'Final summary PID differs from boot evidence.')
    if platform in ('linux', 'win32'):
        require(fields.get('arguments_preserved') == 'true' and
                values('arguments_preserved') == ['true'] * (cycles + 1),
                'Original arguments were not verified on every boot.')
    if platform == 'linux':
        require(fields.get('deferred_failure_recovered') == 'true' and
                values('linux_preflight_failure_recovered') == ['true'] and
                values('linux_exec_failure_preserved_app') == ['true'] and
                'restart_app: execv failed; keeping current process alive' in native_log,
                'Missing native Linux failure recovery evidence.')
    return dict(run_id=run_id, platform=platform, requested_cycles=cycles,
                alternating_modes_verified=True, boot_pids=pids,
                summary=summary, results=result, state=state, native_log=native_log)


def cycle_count(value: str) -> int:
    count = int(value)
    if count < 1 or count > 1000:
        raise argparse.ArgumentTypeError('cycles must be between 1 and 1000')
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('executable', type=Path)
    parser.add_argument('--output', type=Path, default=Path('desktop-proof.json'))
    parser.add_argument('--cycles', type=cycle_count, default=30)
    args = parser.parse_args()
    executable = args.executable.resolve()
    directories = [Path.home() / 'restart_app_ci_proof']
    if executable.suffix == '.app':
        with (executable / 'Contents/Info.plist').open('rb') as stream:
            info = plistlib.load(stream)
        directories.insert(0, Path.home() / 'Library/Containers' /
                           info['CFBundleIdentifier'] / 'Data/restart_app_ci_proof')
        executable = executable / 'Contents/MacOS' / info['CFBundleExecutable']
    existing_processes = find_proof_processes(executable)
    if existing_processes:
        raise RuntimeError(f'The disposable executable is already running: {sorted(existing_processes)}')
    for directory in directories:
        for name in ['state.json', 'run_id.txt', 'restart_proof.txt',
                     'restart_result.txt', 'restart_failure.txt']:
            (directory / name).unlink(missing_ok=True)
    run_id = uuid.uuid4().hex
    environment = dict(os.environ, RESTART_APP_PROOF_RUN_ID=run_id,
                       RESTART_APP_PROOF_CYCLES=str(args.cycles))
    command = [str(executable)]
    if sys.platform in ('linux', 'win32'):
        command.append('restart proof "quoted" café 東京')
    original_mode = executable.stat().st_mode
    log_file = args.output.with_suffix('.log')
    log_stream = log_file.open('w', encoding='utf-8')
    process = subprocess.Popen(command, env=environment, stdout=log_stream,
                               stderr=subprocess.STDOUT)
    evidence = None
    try:
        timeout = 30 + args.cycles * 10
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline and evidence is None:
            for directory in directories:
                failure = directory / 'restart_failure.txt'
                if failure.exists():
                    raise RuntimeError(failure.read_text())
                proof = directory / 'restart_proof.txt'
                if not proof.exists():
                    continue
                state = json.loads((directory / 'state.json').read_text())
                result = (directory / 'restart_result.txt').read_text()
                summary = proof.read_text()
                native_log = log_file.read_text(encoding='utf-8', errors='replace')
                evidence = validate_proof(run_id=run_id, cycles=args.cycles,
                                          platform=sys.platform, state=state,
                                          result=result, summary=summary,
                                          native_log=native_log)
                evidence['live_processes_before_cleanup'] = wait_for_only_final_process(
                    executable, int(state['lastPid']))
                evidence['obsolete_processes_remaining'] = []
                break
            if evidence is None:
                time.sleep(0.5)
        if evidence is None:
            raise TimeoutError(f'The application did not produce restart proof within {timeout} seconds.')
    finally:
        if sys.platform == 'linux':
            # Recover the disposable executable even when its failure probe
            # crashes before its own finally block restores the execute bits.
            backup = executable.with_name(
                f'{executable.name}.restart-proof-backup-{run_id}')
            if backup.exists():
                backup.replace(executable)
            executable.chmod(original_mode)
        # Terminate only processes recorded by this run of the disposable app.
        pids = {process.pid} if process.poll() is None else set()
        for directory in directories:
            try:
                current = json.loads((directory / 'state.json').read_text())
                if current['runId'] == run_id and current.get('lastPid'):
                    pids.add(int(current['lastPid']))
                    results = (directory / 'restart_result.txt').read_text()
                    pids.update(int(value) for value in
                                re.findall(r'^pid=(\d+)$', results, re.MULTILINE))
            except (OSError, ValueError, KeyError):
                pass
        for pid in pids:
            proof_process(pid, executable, terminate=True)
        try:
            process.wait(timeout=10)
            deadline = time.monotonic() + 5
            remaining = {pid for pid in pids if proof_process(pid, executable)}
            while remaining and time.monotonic() < deadline:
                time.sleep(0.1)
                remaining = {pid for pid in pids if proof_process(pid, executable)}
            if remaining:
                raise RuntimeError(f'Owned proof processes survived cleanup: {sorted(remaining)}')
        finally:
            log_stream.close()
    evidence['owned_processes_after_cleanup'] = []
    args.output.write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(evidence, indent=2), flush=True)


if __name__ == '__main__':
    main()
