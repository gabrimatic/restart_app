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


def terminate_proof_process(pid: int, executable: Path) -> None:
    """Check executable identity before touching a recorded, possibly reused PID."""
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
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        kernel.CloseHandle.restype = wintypes.BOOL
        handle = kernel.OpenProcess(0x1001, False, pid)
        if not handle:
            return
        try:
            name = ctypes.create_unicode_buffer(32768)
            size = wintypes.DWORD(len(name))
            if kernel.QueryFullProcessImageNameW(handle, 0, name, ctypes.byref(size)):
                if os.path.normcase(os.path.realpath(name.value)) == os.path.normcase(str(executable)):
                    kernel.TerminateProcess(handle, 0)
        finally:
            kernel.CloseHandle(handle)
        return

    if sys.platform == 'linux':
        try:
            name = os.readlink(f'/proc/{pid}/exe')
        except FileNotFoundError:
            return
        name = name.removesuffix(' (deleted)')
    else:
        query = subprocess.run(['ps', '-ww', '-p', str(pid), '-o', 'comm='],
                               capture_output=True, text=True, check=False)
        name = query.stdout.strip()
    if name and Path(name).resolve() == executable:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('executable', type=Path)
    parser.add_argument('--output', type=Path, default=Path('desktop-proof.json'))
    args = parser.parse_args()
    executable = args.executable.resolve()
    directories = [Path.home() / 'restart_app_ci_proof']
    if executable.suffix == '.app':
        with (executable / 'Contents/Info.plist').open('rb') as stream:
            info = plistlib.load(stream)
        directories.insert(0, Path.home() / 'Library/Containers' /
                           info['CFBundleIdentifier'] / 'Data/restart_app_ci_proof')
        executable = executable / 'Contents/MacOS' / info['CFBundleExecutable']
    for directory in directories:
        for name in ['state.json', 'run_id.txt', 'restart_proof.txt',
                     'restart_result.txt', 'restart_failure.txt']:
            (directory / name).unlink(missing_ok=True)
    run_id = uuid.uuid4().hex
    environment = dict(os.environ, RESTART_APP_PROOF_RUN_ID=run_id)
    command = [str(executable)]
    if sys.platform in ('linux', 'win32'):
        command.append('restart proof "quoted" café 東京')
    original_mode = executable.stat().st_mode
    log_file = args.output.with_suffix('.log')
    log_stream = log_file.open('w', encoding='utf-8')
    process = subprocess.Popen(command, env=environment, stdout=log_stream,
                               stderr=subprocess.STDOUT)
    state = None
    try:
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
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
                markers = ['RESTARTED_OK', f'run_id={run_id}', 'launches=11',
                           'restarts=10', 'state_reset=true', 'state_persisted=true',
                           'concurrent_requests_rejected=10']
                if sys.platform in ('linux', 'win32'):
                    markers.append('arguments_preserved=true')
                    if result.count('arguments_preserved=true') != 11:
                        raise RuntimeError('Arguments were not verified on every boot.')
                native_log = log_file.read_text(encoding='utf-8', errors='replace')
                if sys.platform == 'linux':
                    markers.append('deferred_failure_recovered=true')
                    if ('linux_preflight_failure_recovered=true' not in result or
                            'linux_exec_failure_preserved_app=true' not in result or
                            'restart_app: execv failed; keeping current process alive' not in native_log):
                        raise RuntimeError('Missing native Linux failure recovery evidence.')
                for marker in markers:
                    if marker not in summary:
                        raise RuntimeError(f'Missing proof marker: {marker}\n{summary}')
                if result.count('success=true') != 10 or result.count('code=UNSUPPORTED_RESTART_MODE') != 2:
                    raise RuntimeError(f'Unexpected native results:\n{result}')
                if result.count('duplicate_code=RESTART_ALREADY_IN_PROGRESS') != 10:
                    raise RuntimeError(f'Concurrent native requests were not rejected:\n{result}')
                if state['runId'] != run_id or not state['complete']:
                    raise RuntimeError(f'Wrong run identity or incomplete state: {state}')
                evidence = dict(run_id=run_id, platform=sys.platform,
                                summary=summary, results=result, state=state,
                                native_log=native_log)
                args.output.write_text(json.dumps(evidence, indent=2) + '\n')
                print(json.dumps(evidence, indent=2), flush=True)
                return
            time.sleep(0.5)
        raise TimeoutError('The application did not produce restart proof within 120 seconds.')
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
            terminate_proof_process(pid, executable)
        try:
            process.wait(timeout=10)
        finally:
            log_stream.close()


if __name__ == '__main__':
    main()
