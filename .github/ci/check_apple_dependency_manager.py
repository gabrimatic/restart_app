#!/usr/bin/env python3
"""Prepare an Apple consumer and verify the dependency manager actually used."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


def prepare(consumer: Path) -> None:
    # Older Flutter templates predate the plugin's existing macOS 10.15 floor.
    project = consumer / 'macos/Runner.xcodeproj/project.pbxproj'

    def deployment_target(match: re.Match[str]) -> str:
        version = tuple(map(int, match[1].split('.')))
        return ('MACOSX_DEPLOYMENT_TARGET = 10.15;'
                if version < (10, 15) else match[0])

    project.write_text(re.sub(r'MACOSX_DEPLOYMENT_TARGET = ([0-9.]+);',
                              deployment_target, project.read_text()))
    podfile = consumer / 'macos/Podfile'
    if podfile.exists():
        text = podfile.read_text()
        pattern = r"(?m)^\s*#?\s*platform :osx, ['\"]([0-9.]+)['\"]"
        match = re.search(pattern, text)
        if match and tuple(map(int, match[1].split('.'))) < (10, 15):
            text = text[:match.start()] + "platform :osx, '10.15'" + text[match.end():]
        podfile.write_text(text)


def verify(consumer: Path, manager: str) -> None:
    metadata = json.loads((consumer / '.flutter-plugins-dependencies').read_text())
    enabled = metadata.get('swift_package_manager_enabled', False)
    for platform in ['ios', 'macos']:
        platform_enabled = enabled.get(platform, False) if isinstance(enabled, dict) else enabled
        if manager == 'SwiftPM':
            if platform_enabled is not True:
                raise RuntimeError(f'{platform}: SwiftPM was not enabled in plugin metadata')
            manifests = [path for path in (consumer / platform / 'Flutter').rglob('Package.swift')
                         if path.parent.name == 'FlutterGeneratedPluginSwiftPackage']
            if not any('restart_app' in path.read_text() and 'restart-app' in path.read_text()
                       for path in manifests):
                raise RuntimeError(f'{platform}: restart_app is absent from the generated SwiftPM graph')
            project = consumer / platform / 'Runner.xcodeproj/project.pbxproj'
            if 'FlutterGeneratedPluginSwiftPackage' not in project.read_text():
                raise RuntimeError(f'{platform}: Xcode does not reference the generated SwiftPM package')
            lockfile = consumer / platform / 'Podfile.lock'
            if lockfile.exists() and re.search(r'(?m)^  - restart_app \(', lockfile.read_text()):
                raise RuntimeError(f'{platform}: restart_app silently fell back to CocoaPods')
        else:
            if platform_enabled:
                raise RuntimeError(f'{platform}: SwiftPM unexpectedly enabled in a CocoaPods check')
            lockfile = consumer / platform / 'Podfile.lock'
            if not lockfile.exists() or not re.search(r'(?m)^  - restart_app \(', lockfile.read_text()):
                raise RuntimeError(f'{platform}: restart_app is absent from Podfile.lock')
        print(f'{platform}: restart_app verified through {manager}', flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('consumer', type=Path)
    parser.add_argument('--prepare', action='store_true')
    parser.add_argument('--manager', choices=['SwiftPM', 'CocoaPods'])
    args = parser.parse_args()
    if args.prepare:
        prepare(args.consumer.resolve())
    elif args.manager:
        verify(args.consumer.resolve(), args.manager)
    else:
        parser.error('Specify --prepare or --manager')


if __name__ == '__main__':
    main()
