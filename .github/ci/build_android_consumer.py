#!/usr/bin/env python3
"""Build a disposable Android app that stress-tests native restarts on launch."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess


def run(*arguments: str, cwd: Path) -> None:
    subprocess.run(arguments, cwd=cwd, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--minimum', action='store_true')
    parser.add_argument('--target-sdk', type=int, default=37)
    parser.add_argument('--compile-minor', type=int)
    args = parser.parse_args()
    directory = args.directory.resolve()
    if directory.exists():
        parser.error('Choose a new directory for the disposable consumer.')
    package = Path(__file__).resolve().parents[2]
    run('flutter', 'create', '--platforms=android', '--project-name',
        'restart_android_proof', str(directory), cwd=package)
    (directory / 'pubspec.yaml').write_text(f'''name: restart_android_proof
publish_to: none
environment:
  sdk: '>=3.4.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  restart_app:
    path: {json.dumps(str(package))}
  shared_preferences: 2.2.3
flutter:
  uses-material-design: true
''')
    shutil.copyfile(package / '.github/ci/android_proof_main.dart', directory / 'lib/main.dart')
    shutil.rmtree(directory / 'test', ignore_errors=True)
    (directory / 'analysis_options.yaml').write_text('analyzer:\n  errors:\n    unused_import: error\n')
    if args.minimum:
        # Match the plugin's documented Java 17 / AGP 8 / Kotlin 2 toolchain.
        # Flutter 3.22's default template predates those package requirements.
        settings = directory / 'android/settings.gradle'
        text = settings.read_text().replace('version "7.3.0"', 'version "8.5.2"')
        text = text.replace('version "1.7.10"', 'version "2.0.21"')
        settings.write_text(text)
        wrapper = directory / 'android/gradle/wrapper/gradle-wrapper.properties'
        wrapper.write_text(re.sub(r'gradle-[\d.]+-(all|bin)', 'gradle-8.7-all', wrapper.read_text()))
    application = directory / 'android/app/build.gradle'
    if application.exists():
        text = application.read_text()
        text = text.replace('ndkVersion = flutter.ndkVersion', 'ndkVersion = "26.1.10909125"')
        text = text.replace('JavaVersion.VERSION_1_8', 'JavaVersion.VERSION_17')
        text = text.replace('    defaultConfig {', '    kotlinOptions { jvmTarget = "17" }\n\n    defaultConfig {')
    else:
        application = directory / 'android/app/build.gradle.kts'
        text = application.read_text()
    compile_sdk = f'compileSdk = {args.target_sdk}'
    if args.compile_minor is not None:
        if application.suffix != '.kts':
            parser.error('--compile-minor requires a current Kotlin DSL template.')
        compile_sdk = (f'compileSdk {{ version = release({args.target_sdk}) {{ '
                       f'minorApiLevel = {args.compile_minor} }} }}')
    text = text.replace('compileSdk = flutter.compileSdkVersion', compile_sdk)
    text = text.replace('targetSdk = flutter.targetSdkVersion', f'targetSdk = {args.target_sdk}')
    text = text.replace('minSdk = flutter.minSdkVersion', f'minSdk = {21 if args.minimum else 24}')
    application.write_text(text)
    run('flutter', 'pub', 'get', cwd=directory)
    run('flutter', 'analyze', cwd=directory)
    run('flutter', 'build', 'apk', '--debug', cwd=directory)
    print(directory / 'build/app/outputs/flutter-apk/app-debug.apk')


if __name__ == '__main__':
    main()
