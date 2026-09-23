#!/usr/bin/env python3
"""Install the disposable Android probe and verify fifteen native restarts."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET


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

    package = 'com.example.restart_android_proof'
    print(adb('install', '-r', str(args.apk.resolve()), timeout=90), flush=True)
    print(adb('shell', 'pm', 'clear', package), flush=True)
    print(adb('shell', 'am', 'start', '-n', f'{package}/.MainActivity'), flush=True)
    deadline = time.monotonic() + 240
    last = ''
    while time.monotonic() < deadline:
        try:
            adb('shell', 'uiautomator', 'dump', '/data/local/tmp/restart-proof.xml', timeout=15)
            root = ET.fromstring(adb('shell', 'cat', '/data/local/tmp/restart-proof.xml'))
            texts = [node.get('text', '') for node in root.iter('node')]
            last = '\n'.join(texts)
            if any(text.startswith('FAIL ') for text in texts):
                raise RuntimeError(last)
            if any(text.startswith('PASS 15 Android restarts') for text in texts):
                records = re.findall(r'cycle=(\d+) boot=(\d+) pid=(\d+) dirty=(\d+)', last)
                if len(records) != 16 or [int(row[0]) for row in records] != list(range(16)):
                    raise RuntimeError(f'Incomplete launch history: {last}')
                if len({row[1] for row in records}) != 16 or any(row[3] != '0' for row in records):
                    raise RuntimeError(f'Dart state did not reset: {last}')
                try:
                    page_size = adb('shell', 'getconf', 'PAGESIZE').strip()
                except subprocess.CalledProcessError:
                    page_size = 'unavailable on this emulator'
                evidence = dict(serial=args.serial,
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
        time.sleep(1)
    raise TimeoutError(f'No completed Android proof after 240 seconds. Last UI:\n{last}')


if __name__ == '__main__':
    main()
