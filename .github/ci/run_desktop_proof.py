#!/usr/bin/env python3
"""Run the built desktop application and require fresh native restart evidence."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import time
import uuid


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
    process = subprocess.Popen([str(executable)], env=environment)
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
                for marker in ['RESTARTED_OK', f'run_id={run_id}', 'launches=11',
                               'restarts=10', 'state_reset=true', 'state_persisted=true']:
                    if marker not in summary:
                        raise RuntimeError(f'Missing proof marker: {marker}\n{summary}')
                if result.count('success=true') != 10 or result.count('code=UNSUPPORTED_RESTART_MODE') != 2:
                    raise RuntimeError(f'Unexpected native results:\n{result}')
                if state['runId'] != run_id or not state['complete']:
                    raise RuntimeError(f'Wrong run identity or incomplete state: {state}')
                evidence = dict(run_id=run_id, platform=sys.platform,
                                summary=summary, results=result, state=state)
                args.output.write_text(json.dumps(evidence, indent=2) + '\n')
                print(json.dumps(evidence, indent=2), flush=True)
                return
            time.sleep(0.5)
        raise TimeoutError('The application did not produce restart proof within 120 seconds.')
    finally:
        # Terminate only processes recorded by this run of the disposable app.
        pids = {process.pid} if process.poll() is None else set()
        for directory in directories:
            try:
                current = json.loads((directory / 'state.json').read_text())
                if current['runId'] == run_id and current.get('lastPid'):
                    pids.add(int(current['lastPid']))
            except (OSError, ValueError, KeyError):
                pass
        for pid in pids:
            try:
                if sys.platform == 'win32':
                    subprocess.run(['taskkill', '/PID', str(pid), '/F'],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                else:
                    os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        process.wait(timeout=10)


if __name__ == '__main__':
    main()
