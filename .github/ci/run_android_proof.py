#!/usr/bin/env python3
"""Install the disposable Android probe and verify fifteen native restarts."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import time
import uuid
import xml.etree.ElementTree as ET

PACKAGE = 'com.example.restart_android_proof'


def ui_texts(root: ET.Element) -> list[str]:
    """Read native text and Flutter semantics labels without duplicate entries."""
    return list(dict.fromkeys(
        label for node in root.iter('node') if node.get('package') == PACKAGE
        if (label := node.get('text') or node.get('content-desc'))
    ))


def proof_records(text: str, started_us: int) -> list[tuple[str, ...]] | None:
    records = re.findall(r'cycle=(\d+) boot=(\d+) pid=(\d+) dirty=(\d+)', text)
    # Accessibility can briefly retain an old screen after clearing the app.
    if not records or int(records[0][1]) < started_us:
        return None
    if len(records) != 16 or [int(row[0]) for row in records] != list(range(16)):
        raise RuntimeError(f'Incomplete launch history: {text}')
    if len({row[1] for row in records}) != 16 or any(row[3] != '0' for row in records):
        raise RuntimeError(f'Dart state did not reset: {text}')
    return records


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--output', type=Path, default=Path('android-proof.json'))
    args = parser.parse_args()
    command = ['adb', '-s', args.serial]

    def adb(*arguments: str, timeout: int = 30) -> str:
        return subprocess.check_output(command + list(arguments), text=True,
                                       stderr=subprocess.STDOUT, timeout=timeout)

    print(adb('install', '-r', str(args.apk.resolve()), timeout=90), flush=True)
    started_us = int(adb('shell', 'date', '+%s').strip()) * 1_000_000
    cleared = adb('shell', 'pm', 'clear', PACKAGE)
    if cleared.strip() != 'Success':
        raise RuntimeError(f'Could not clear disposable app: {cleared}')
    print(cleared, flush=True)
    print(adb('shell', 'am', 'start', '-n', f'{PACKAGE}/.MainActivity'), flush=True)
    deadline = time.monotonic() + 240
    last = ''
    run_id = uuid.uuid4().hex
    attempt = 0
    while time.monotonic() < deadline:
        attempt += 1
        dump_path = f'/data/local/tmp/restart-proof-{run_id}-{attempt}.xml'
        try:
            dumped = adb('shell', 'uiautomator', 'dump', dump_path, timeout=15)
            if f'UI hierchary dumped to: {dump_path}' not in dumped:
                continue
            root = ET.fromstring(adb('shell', 'cat', dump_path))
            texts = ui_texts(root)
            last = '\n'.join(texts)
            if any(text.startswith('FAIL ') for text in texts):
                raise RuntimeError(last)
            if any(text.startswith('PASS 15 Android restarts') for text in texts):
                records = proof_records(last, started_us)
                if records is None:
                    continue
                try:
                    page_size = adb('shell', 'getconf', 'PAGESIZE').strip()
                except subprocess.CalledProcessError:
                    page_size = 'unavailable on this emulator'
                evidence = dict(run_id=run_id, started_us=started_us,
                                serial=args.serial,
                                api=adb('shell', 'getprop', 'ro.build.version.sdk').strip(),
                                android=adb('shell', 'getprop', 'ro.build.version.release').strip(),
                                page_size=page_size,
                                records=records, result=last)
                args.output.write_text(json.dumps(evidence, indent=2) + '\n')
                screenshot = args.output.with_suffix('.png')
                screenshot.write_bytes(subprocess.check_output(command + ['exec-out', 'screencap', '-p']))
                print(json.dumps(evidence, indent=2), flush=True)
                return
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, ET.ParseError):
            # UI automation can disconnect while the task/engine is replaced.
            pass
        finally:
            try:
                adb('shell', 'rm', '-f', dump_path)
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                pass
        time.sleep(1)
    raise TimeoutError(f'No completed Android proof after 240 seconds. Last UI:\n{last}')


if __name__ == '__main__':
    main()
