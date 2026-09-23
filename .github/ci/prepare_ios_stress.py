#!/usr/bin/env python3
"""Create a disposable iOS lifecycle consumer from a candidate package archive."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import uuid

from candidate_package import assert_package_origin, package_directory
from package_archive import inspect_archive, verify_extracted


def run(*args: str, cwd: Path) -> None:
    subprocess.run(args, cwd=cwd, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('consumer', type=Path)
    parser.add_argument('--cycles', type=int, required=True)
    parser.add_argument('--sha256', required=True)
    args = parser.parse_args()
    if args.cycles < 10 or args.cycles % 10:
        parser.error('--cycles must be a positive multiple of 10')
    archive = args.archive.resolve()
    actual_sha = hashlib.sha256(archive.read_bytes()).hexdigest()
    if actual_sha != args.sha256:
        raise RuntimeError(f'Archive SHA differs: expected {args.sha256}, got {actual_sha}')
    consumer = args.consumer.resolve()
    if consumer.exists():
        raise RuntimeError(f'Refusing to replace existing consumer: {consumer}')
    source = Path(__file__).resolve().parent
    run('flutter', 'create', '--platforms=ios', '--org=info.gabrimatic',
        '--project-name=restart_app_ios_stress', str(consumer), cwd=consumer.parent)
    package = consumer / 'candidate_package'
    payload_manifest = inspect_archive(archive, package)
    verify_extracted(package, payload_manifest)
    (consumer / 'stress-package-manifest.json').write_text(
        json.dumps(payload_manifest, ensure_ascii=False, indent=2) + '\n')
    package_directory(package)

    # Use the example constraints and its lockfile when that file is in the archive.
    example_pubspec = (package / 'example/pubspec.yaml').read_text()
    dependencies = example_pubspec.split('dependencies:\n', 1)[1].split('\ndev_dependencies:', 1)[0]
    dependencies = dependencies.replace('    path: ../', '    path: candidate_package')
    (consumer / 'pubspec.yaml').write_text(
        'name: restart_app_ios_stress\npublish_to: none\nversion: 1.0.0+1\n'
        'environment:\n  sdk: ">=3.10.0 <4.0.0"\n'
        'dependencies:\n' + dependencies + '\n'
        'dev_dependencies:\n  flutter_test:\n    sdk: flutter\n'
        'flutter:\n  uses-material-design: true\n'
    )
    example_lock = package / 'example/pubspec.lock'
    if example_lock.is_file():
        (consumer / 'pubspec.lock').write_bytes(example_lock.read_bytes())
    (consumer / 'lib/main.dart').write_text((source / 'ios_stress_main.dart').read_text())
    run_id = str(uuid.uuid4())
    host = (source / 'ios_stress_host.swift').read_text()
    for key, value in {
        '__RUN_ID__': run_id, '__ARCHIVE_SHA__': actual_sha,
        '__PACKAGE_ROOT__': str(package),
    }.items():
        host = host.replace('"' + key + '"', json.dumps(value, ensure_ascii=False))
    host = host.replace('__CYCLES__', str(args.cycles))
    (consumer / 'ios/Runner/AppDelegate.swift').write_text(host)
    tests = consumer / 'ios/RunnerUITests'
    tests.mkdir()
    (tests / 'RestartStressUITests.swift').write_text(
        (source / 'ios_stress_uitests.swift').read_text().replace('__CYCLES__', str(args.cycles))
    )
    config = {
        'runID': run_id, 'cycles': args.cycles, 'archiveSHA256': actual_sha,
        'archive': str(archive), 'resolvedPackageRoot': str(package),
        'payloadSHA256': payload_manifest['payloadSha256'],
        'bundleID': 'info.gabrimatic.restartapp.stress', 'settleMilliseconds': 2000,
        'exampleLockApplied': example_lock.is_file(),
    }
    (consumer / 'stress-config.json').write_text(json.dumps(config, indent=2) + '\n')
    ruby = '''require 'xcodeproj'
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
runner = project.targets.find { |target| target.name == 'Runner' }
runner.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'info.gabrimatic.restartapp.stress'
end
tests = project.new_target(:ui_test_bundle, 'RunnerUITests', :ios, '15.0')
tests.add_dependency(runner)
group = project.main_group.new_group('RunnerUITests', 'RunnerUITests')
tests.add_file_references([group.new_file('RestartStressUITests.swift')])
tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'info.gabrimatic.restartapp.stress.uitests'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TEST_TARGET_NAME'] = 'Runner'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
end
project.save
scheme = Xcodeproj::XCScheme.new('ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme')
scheme.add_build_target(tests, false)
scheme.add_test_target(tests)
scheme.save_as('ios/Runner.xcodeproj', 'Runner')
'''
    (consumer / 'prepare_ui_target.rb').write_text(ruby)
    run('ruby', 'prepare_ui_target.rb', cwd=consumer)
    run('flutter', 'pub', 'get', cwd=consumer)
    assert_package_origin(consumer, package, required_platforms=('ios',))
    verify_extracted(package, payload_manifest)
    config_file = json.loads((consumer / '.dart_tool/package_config.json').read_text())
    resolved = next(item for item in config_file['packages'] if item['name'] == 'restart_app')
    config['packageConfigRootUri'] = resolved['rootUri']
    config['pubspecLockSHA256'] = hashlib.sha256((consumer / 'pubspec.lock').read_bytes()).hexdigest()
    config['qaSourceSHA256'] = {
        name: hashlib.sha256((source / name).read_bytes()).hexdigest()
        for name in ['ios_stress_main.dart', 'ios_stress_host.swift', 'ios_stress_uitests.swift']
    }
    dependencies = subprocess.check_output(['flutter', 'pub', 'deps', '--json'], cwd=consumer, text=True)
    (consumer / 'stress-dependencies.json').write_text(dependencies)
    (consumer / 'stress-config.json').write_text(json.dumps(config, indent=2) + '\n')
    print(json.dumps(config, indent=2))


if __name__ == '__main__':
    main()
