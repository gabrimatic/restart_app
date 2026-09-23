#!/usr/bin/env python3
"""Verify controlled Android restarts, background/resume and Activity recreation."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import shlex
import subprocess
import time
import uuid
import xml.etree.ElementTree as ET

PACKAGE = 'com.example.restart_android_proof'
KINDS = ('platformDefault', 'process', 'forceKill')


def control_file_script(name: str, value: dict) -> str:
    """Write a small literal JSON command without depending on ADB stdin EOF."""
    if name not in ('config', 'command'):
        raise ValueError('Unexpected proof control filename')
    base = f'files/restart-proof-{name}'
    # JSON occupies one line, so no string value can become the quoted heredoc
    # delimiter. Quoting it also disables every shell expansion in the body.
    script = (f"cat > {base}.tmp <<'RESTART_PROOF_JSON' && mv {base}.tmp {base}.json\n"
              f'{json.dumps(value)}\nRESTART_PROOF_JSON\n')
    # API 21's shell materializes heredocs under TMPDIR. Set it before that
    # shell parses the body, since run-as cannot write the shell default.
    return f'TMPDIR="$PWD/files" sh -c {shlex.quote(script)}'


def private_file_script(name: str) -> str:
    """Return empty content for an absent file, also on legacy ADB shells."""
    if name not in ('config.json', 'command.json', 'ready.json', 'failure.json',
                    'summary.json', 'native.jsonl', 'dart.jsonl'):
        raise ValueError('Unexpected proof evidence filename')
    path = f'files/restart-proof-{name}'
    return f'if [ -f {path} ]; then cat {path}; fi'


def page_size_evidence(output: str) -> dict:
    """Keep an unavailable measurement distinct from the shell diagnostic."""
    value = output.strip()
    if value.isascii() and value.isdecimal() and int(value) > 0:
        return {'page_size': int(value)}
    return {'page_size': None, 'page_size_error': value or 'Empty getconf response'}


def ui_texts(root: ET.Element) -> list[str]:
    """Read native text and Flutter semantics labels without duplicate entries."""
    return list(dict.fromkeys(
        label for node in root.iter('node') if node.get('package') == PACKAGE
        if (label := node.get('text') or node.get('content-desc'))
    ))


def validate_summary(summary: dict, run_id: str, cycles: int, started_us: int) -> dict:
    history = summary.get('history', [])
    requests = summary.get('requests', [])
    if (summary.get('runId') != run_id or summary.get('requestedCycles') != cycles or
            summary.get('complete') is not True):
        raise RuntimeError('Wrong proof run, requested count or completion state')
    if len(history) != cycles + 1 or [row.get('cycle') for row in history] != list(range(cycles + 1)):
        raise RuntimeError('Incomplete native restart history')
    boots = [row.get('boot', '') for row in history]
    if (len(set(boots)) != cycles + 1 or
            any(not str(boot).isdecimal() or int(boot) < started_us for boot in boots) or
            any(row.get('dirty') != 0 or not isinstance(row.get('pid'), int) or row['pid'] <= 0 for row in history)):
        raise RuntimeError('Dart boot identity, freshness or state reset failed')
    if len(requests) != cycles:
        raise RuntimeError('Incomplete native request evidence')
    for cycle, request in enumerate(requests):
        kind = KINDS[cycle % 3]
        if (request.get('cycle') != cycle or request.get('kind') != kind or
                request.get('mode') != ('process' if kind == 'process' else 'platformDefault') or
                request.get('forceKill') is not (kind == 'forceKill') or
                request.get('resolvedMode') != ('platformDefault' if kind == 'platformDefault' else 'process') or
                request.get('duplicatesRejected') != 8 or request.get('unsupportedRejected') != 2):
            raise RuntimeError(f'Wrong restart/concurrency/mode evidence at cycle {cycle}')
        if kind != 'platformDefault' and history[cycle]['pid'] == history[cycle + 1]['pid']:
            raise RuntimeError(f'{kind} retained the old process at cycle {cycle}')
    if summary.get('finalPid') != history[-1]['pid']:
        raise RuntimeError('Lifecycle recreation changed the process unexpectedly')
    return dict(mode_counts=dict(Counter(request['kind'] for request in requests)),
                native_restart_count=cycles, fresh_restart_boots=len(boots),
                duplicate_requests_rejected=cycles * 8, unsupported_requests_rejected=cycles * 2)


def verify_lifecycle(before: dict, after: dict, native: list[dict], dart: list[dict], *, rotation: bool) -> None:
    if before['cycle'] != after['cycle'] or before['pid'] != after['pid'] or after['dirty'] != 0:
        raise RuntimeError('Lifecycle transition changed the persisted restart counter or PID')
    if rotation:
        if before['boot'] == after['boot'] or before['activity'] == after['activity'] or after['kind'] != 'rotation':
            raise RuntimeError('Rotation did not recreate the Activity with fresh Dart state')
        destroyed = next((index for index, event in enumerate(native)
                          if event['event'] == 'onDestroy' and event['activity'] == before['activity']), None)
        created = next((index for index, event in enumerate(native)
                        if event['event'] == 'onCreate' and event['activity'] == after['activity']), None)
        if destroyed is None or created is None or destroyed >= created:
            raise RuntimeError('Missing ordered native Activity destruction/recreation during rotation')
        if not any(event['event'] == 'boot' and event['boot'] == after['boot'] and event.get('kind') == 'rotation'
                   for event in dart):
            raise RuntimeError('Missing fresh Dart rotation boot')
    else:
        if before['boot'] != after['boot'] or before['activity'] != after['activity']:
            raise RuntimeError('Home/resume unexpectedly replaced Activity or Dart state')
        native_states = [event['event'] for event in native if event['activity'] == before['activity']]
        dart_states = [event.get('state') for event in dart if event['event'] == 'lifecycle' and event['boot'] == before['boot']]
        if ('onPause' not in native_states or 'onResume' not in native_states or
                native_states.index('onPause') >= native_states.index('onResume')):
            raise RuntimeError('Missing native background/resume lifecycle events')
        background = next((index for index, state in enumerate(dart_states)
                           if state == 'paused'), None)
        if (background is None or 'resumed' not in dart_states or
                background >= dart_states.index('resumed')):
            raise RuntimeError('Missing Dart background/resume lifecycle events')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--cycles', type=int, help='Defaults to 60 on API 37+, otherwise 30; positive multiple of 30.')
    parser.add_argument('--output', type=Path, default=Path('android-proof.json'))
    args = parser.parse_args()
    command = ['adb', '-s', args.serial]

    def adb(*arguments: str, timeout: int = 30) -> str:
        return subprocess.check_output(command + list(arguments), text=True,
                                       stderr=subprocess.STDOUT, timeout=timeout)

    api = int(adb('shell', 'getprop', 'ro.build.version.sdk').strip())
    cycles = args.cycles if args.cycles is not None else (60 if api >= 37 else 30)
    if cycles <= 0 or cycles % 30 != 0 or cycles > 300:
        parser.error('--cycles must be a positive multiple of 30, up to 300')
    run_id = uuid.uuid4().hex
    original_settings = {key: adb('shell', 'settings', 'get', 'system', key).strip()
                         for key in ('accelerometer_rotation', 'user_rotation')}
    evidence = dict(run_id=run_id, serial=args.serial, api=api, requested_cycles=cycles,
                    original_rotation_settings=original_settings, homes=[], rotations=[], complete=False)
    dump_count = 0
    started_us = 0

    def write_private(name: str, value: dict) -> None:
        # Legacy adbd does not reliably deliver EOF to stdin-fed cat, and API
        # 21 lacks printf. A quoted heredoc supplies literal content and EOF.
        remote = f'run-as {PACKAGE} sh -c {shlex.quote(control_file_script(name, value))}'
        subprocess.run(command + ['shell', remote],
                       text=True, capture_output=True, check=True, timeout=15)
        # Old ADB shell protocols cannot return the remote exit code reliably.
        if json.loads(private_text(f'{name}.json')) != value:
            raise RuntimeError('The device did not persist the exact proof command')

    def private_text(name: str) -> str:
        script = shlex.quote(private_file_script(name))
        return adb('shell', f'run-as {PACKAGE} sh -c {script}', timeout=10)

    def events(name: str) -> list[dict]:
        return [json.loads(line) for line in private_text(f'{name}.jsonl').splitlines() if line]

    def ready(cycle: int, *, previous_boot: str | None = None, orientation: int | None = None) -> dict:
        deadline = time.monotonic() + 35
        while time.monotonic() < deadline:
            try:
                failure = private_text('failure.json')
            except subprocess.CalledProcessError:
                failure = ''
            if failure:
                raise RuntimeError(failure)
            try:
                value = json.loads(private_text('ready.json'))
                if (value['runId'] == run_id and value['cycle'] == cycle and
                        value['boot'] != previous_boot and
                        (orientation is None or value['orientation'] == orientation)):
                    if int(value['boot']) < started_us or value['dirty'] != 0:
                        raise RuntimeError('Stale ready screen or retained Dart state')
                    return value
                if value.get('runId') == run_id and value.get('cycle', -1) > cycle:
                    raise RuntimeError('The app advanced beyond the commanded restart cycle')
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                pass
            time.sleep(0.2)
        raise TimeoutError(f'No fresh ready state for cycle {cycle}, orientation {orientation}')

    def ui(*, visible: bool, token: str = '') -> dict:
        nonlocal dump_count
        deadline = time.monotonic() + 30
        last = ''
        while time.monotonic() < deadline:
            dump_count += 1
            dump_path = f'/data/local/tmp/restart-proof-{run_id}-{dump_count}.xml'
            try:
                result = adb('shell', 'uiautomator', 'dump', dump_path, timeout=15)
                if f'UI hierchary dumped to: {dump_path}' not in result:
                    continue
                last = adb('shell', 'cat', dump_path)
                tree = ET.fromstring(last)
                labels = ui_texts(tree)
                if any(label.startswith('FAIL ') for label in labels):
                    raise RuntimeError('\n'.join(labels))
                present = any(node.get('package') == PACKAGE for node in tree.iter('node'))
                if present == visible and (not visible or any(token in label for label in labels)):
                    return dict(visible=present, text=labels, dump_path=dump_path,
                                sha256=hashlib.sha256(last.encode()).hexdigest())
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired, ET.ParseError):
                pass
            finally:
                try:
                    adb('shell', 'rm', '-f', dump_path)
                except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                    pass
            time.sleep(0.25)
        raise TimeoutError(f'UI visibility did not become {visible} for {token}: {last}')

    try:
        print(adb('install', '-r', str(args.apk.resolve()), timeout=90), flush=True)
        if adb('shell', 'pm', 'clear', PACKAGE).strip() != 'Success':
            raise RuntimeError('Could not clear disposable app data')
        adb('shell', 'run-as', PACKAGE, 'mkdir', '-p', 'files')
        write_private('config', dict(runId=run_id, cycles=cycles))
        adb('shell', 'settings', 'put', 'system', 'accelerometer_rotation', '0')
        adb('shell', 'settings', 'put', 'system', 'user_rotation', '0')
        started_us = int(adb('shell', 'date', '+%s').strip()) * 1_000_000
        evidence['started_us'] = started_us
        adb('shell', 'am', 'start', '-n', f'{PACKAGE}/.MainActivity')
        current = ready(0, orientation=1)
        ui(visible=True, token=f'READY run={run_id} cycle=0 boot={current["boot"]}')
        for cycle in range(cycles + 1):
            if cycle > 0:
                current = ready(cycle)
            if cycle > 0 and cycle % 5 == 0:
                before = current
                native_count, dart_count = len(events('native')), len(events('dart'))
                adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
                hidden = ui(visible=False)
                adb('shell', 'am', 'start', '-n', f'{PACKAGE}/.MainActivity')
                shown = ui(visible=True, token=f'READY run={run_id} cycle={cycle} boot={before["boot"]}')
                current = ready(cycle)
                native, dart = events('native')[native_count:], events('dart')[dart_count:]
                verify_lifecycle(before, current, native, dart, rotation=False)
                evidence['homes'].append(dict(cycle=cycle, before=before, after=current,
                                              hidden=hidden, shown=shown, native=native, dart=dart))
            # Offset rotation from the end of the three-mode sequence so every
            # mode is tested immediately afterward, including the 30-cycle run.
            if cycle % 10 == 5:
                roundtrip = dict(cycle=cycle, transitions=[])
                for rotation, orientation in ((1, 2), (0, 1)):
                    before = current
                    native_count, dart_count = len(events('native')), len(events('dart'))
                    adb('shell', 'settings', 'put', 'system', 'user_rotation', str(rotation))
                    current = ready(cycle, previous_boot=before['boot'], orientation=orientation)
                    shown = ui(visible=True, token=f'READY run={run_id} cycle={cycle} boot={current["boot"]}')
                    native, dart = events('native')[native_count:], events('dart')[dart_count:]
                    verify_lifecycle(before, current, native, dart, rotation=True)
                    roundtrip['transitions'].append(dict(before=before, after=current, shown=shown,
                                                         native=native, dart=dart))
                evidence['rotations'].append(roundtrip)
            action = 'complete' if cycle == cycles else 'restart'
            write_private('command', dict(runId=run_id, cycle=cycle, boot=current['boot'], action=action))
            print(f'run={run_id} completed={cycle}/{cycles} action={action}', flush=True)
        final_ui = ui(visible=True, token=f'PASS {cycles} Android restarts run={run_id}')
        summary = json.loads(private_text('summary.json'))
        evidence.update(validate_summary(summary, run_id, cycles, started_us))
        native, dart = events('native'), events('dart')
        boots = [event for event in dart if event['event'] == 'boot']
        if (len(evidence['homes']) != cycles // 5 or len(evidence['rotations']) != cycles // 10 or
                len(boots) != cycles + 1 + 2 * (cycles // 10) or
                len({event['boot'] for event in boots}) != len(boots) or
                summary['finalBoot'] != current['boot']):
            raise RuntimeError('Incomplete lifecycle stress or duplicated/unexpected Dart boots')
        evidence.update(complete=True, summary=summary, final_ui=final_ui,
                        native_events=native, dart_events=dart, dump_count=dump_count,
                        android=adb('shell', 'getprop', 'ro.build.version.release').strip())
        try:
            evidence.update(page_size_evidence(adb('shell', 'getconf', 'PAGESIZE')))
        except subprocess.CalledProcessError as error:
            evidence.update(page_size=None, page_size_error=error.output.strip() or str(error))
        args.output.with_suffix('.png').write_bytes(
            subprocess.check_output(command + ['exec-out', 'screencap', '-p'], timeout=30))
    except Exception as error:
        evidence['complete'] = False
        evidence['error'] = str(error)
        raise
    finally:
        cleanup_errors = []
        try:
            adb('shell', 'am', 'force-stop', PACKAGE)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            cleanup_errors.append(str(error))
        for key, value in original_settings.items():
            try:
                if value == 'null':
                    adb('shell', 'settings', 'delete', 'system', key)
                else:
                    adb('shell', 'settings', 'put', 'system', key, value)
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
                cleanup_errors.append(str(error))
        restored = {}
        for key in original_settings:
            try:
                restored[key] = adb('shell', 'settings', 'get', 'system', key).strip()
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
                cleanup_errors.append(str(error))
        evidence['restored_rotation_settings'] = restored
        evidence['rotation_settings_restored'] = restored == original_settings
        if cleanup_errors or restored != original_settings:
            evidence['complete'] = False
            evidence['cleanup_errors'] = cleanup_errors
        args.output.write_text(json.dumps(evidence, indent=2) + '\n')
        if cleanup_errors or restored != original_settings:
            raise RuntimeError('Disposable app cleanup or exact emulator settings restoration failed')
    print(json.dumps(evidence, indent=2), flush=True)


if __name__ == '__main__':
    main()
