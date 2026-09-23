#!/usr/bin/env python3
"""Verify notification fallback through the unmodified candidate example UI."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import uuid

from candidate_package import assert_package_origin
from package_archive import inspect_archive, verify_extracted


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


PROBES = ('restart capability', 'shared preferences', 'package info', 'connectivity',
          'url launcher', 'http', 'cache manager', 'file storage', 'sqflite', 'device info',
          'webview', 'dart clean state')


def validate_observations(proof: dict, bundle_id: str, policy: str) -> None:
    """Reject incomplete UI evidence even when XCTest returned successfully."""
    if (proof.get('pass') is not True or proof.get('bundleID') != bundle_id
            or proof.get('policy') != policy or proof.get('permissionPromptObserved') is not True
            or proof.get('cleanupStoppedApp') is not True):
        raise ValueError('Mismatched or incomplete fallback UI evidence')
    prompt = proof.get('permissionPromptLabel', '')
    if f'Restart Fallback {policy.title()}' not in prompt or 'notifications' not in prompt.lower():
        raise ValueError('Observed permission was not this app notification prompt')

    def snapshot(name: str, launches: int) -> dict:
        item = proof[name]
        if (type(item['pid']) is not int or item['pid'] <= 0
                or re.fullmatch(r'boot token: [0-9]+', item['boot']) is None
                or item['allChecksPassed'] is not True or item['dirty'] != 'dart dirty state: 0'
                or item['launches'] != f'launches: {launches}'
                or set(item['probes']) != set(PROBES)):
            raise ValueError(f'Incomplete state snapshot: {name}')
        for probe in PROBES:
            if not item['probes'][probe].startswith(f'{probe}: pass\n'):
                raise ValueError(f'Failed example probe: {probe}')
        token = item['boot'].removeprefix('boot token: ')
        if token not in item['probes']['webview'] or token not in item['probes']['dart clean state']:
            raise ValueError('Stale WebView or Dart boot evidence')
        if launches == 2:
            for probe in ('file storage', 'sqflite'):
                if 'previous boot verified; current boot stored' not in item['probes'][probe]:
                    raise ValueError(f'Missing persistence recovery: {probe}')
        return item

    initial = snapshot('initial', 1)
    if initial['attempts'] != 'restart attempts: 0':
        raise ValueError('Consumer was not fresh')
    if policy == 'denied':
        denied, final = snapshot('afterDenial', 1), snapshot('recovered', 2)
        if (proof.get('alreadyDeniedRejected') is not True or denied['pid'] != initial['pid']
                or denied['boot'] != initial['boot'] or final['pid'] != initial['pid']
                or final['boot'] == initial['boot'] or final['attempts'] != 'restart attempts: 3'):
            raise ValueError('Denial did not preserve the app and permit engine recovery')
    elif policy == 'allowed':
        final = snapshot('reopened', 2)
        if (proof.get('exitObserved') is not True or proof.get('actualNotificationTapped') is not True
                or 'Tap to reopen the example app.' not in proof.get('notificationLabel', '')
                or final['pid'] == initial['pid'] or final['boot'] == initial['boot']
                or final['attempts'] != 'restart attempts: 1'):
            raise ValueError('Notification did not reopen a fresh process with saved state')
    else:
        raise ValueError('Unknown permission case')


def example_source_hashes(root: Path) -> dict[str, str]:
    files = [*sorted((root / 'lib').rglob('*.dart')),
             *sorted((root / 'ios/Runner').rglob('*.swift'))]
    return {str(path.relative_to(root)): digest(path) for path in files}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('consumer', type=Path)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--device', required=True)
    parser.add_argument('--policy', choices=('denied', 'allowed'), required=True)
    args = parser.parse_args()
    archive, consumer = args.archive.resolve(), args.consumer.resolve()
    if digest(archive) != args.sha256:
        raise ValueError('Unexpected candidate archive hash')
    if consumer.exists():
        raise ValueError(f'Refusing to replace existing consumer: {consumer}')
    package = consumer / 'candidate_package'
    manifest = inspect_archive(archive, package)
    shutil.copytree(package / 'example', consumer, dirs_exist_ok=True)
    pubspec = consumer / 'pubspec.yaml'
    source = pubspec.read_text()
    dependency = '  restart_app:\n    path: ../\n'
    if source.count(dependency) != 1:
        raise ValueError('Expected one restart_app path dependency')
    pubspec.write_text(source.replace(dependency, '  restart_app:\n    path: candidate_package\n'))
    run_id = uuid.uuid4().hex
    bundle_id = f'info.gabrimatic.restartapp.fallback.{args.policy}.r{run_id[:12]}'
    info_file = consumer / 'ios/Runner/Info.plist'
    info = plistlib.loads(info_file.read_bytes())
    info['CFBundleDisplayName'] = f'Restart Fallback {args.policy.title()}'
    info_file.write_bytes(plistlib.dumps(info))
    test_source = Path(__file__).with_name('ios_fallback_uitests.swift')
    tests = consumer / 'ios/RunnerUITests'
    tests.mkdir()
    (tests / 'NotificationFallbackUITests.swift').write_text(
        test_source.read_text().replace('__BUNDLE_ID__', bundle_id).replace('__POLICY__', args.policy))
    ruby = '''require 'xcodeproj'
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
runner = project.targets.find { |target| target.name == 'Runner' }
runner.build_configurations.each { |config| config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = ARGV[0] }
tests = project.new_target(:ui_test_bundle, 'RunnerUITests', :ios, '15.0')
tests.add_dependency(runner)
group = project.main_group.new_group('RunnerUITests', 'RunnerUITests')
tests.add_file_references([group.new_file('NotificationFallbackUITests.swift')])
tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = ARGV[0] + '.uitests'
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
    (consumer / 'prepare_fallback.rb').write_text(ruby)
    subprocess.run(['ruby', 'prepare_fallback.rb', bundle_id], cwd=consumer, check=True)
    # The normal example's Dart and host lifecycle implementation stay byte-identical.
    source_hashes = example_source_hashes(package / 'example')
    if example_source_hashes(consumer) != source_hashes:
        raise ValueError('Example Dart or Swift lifecycle source changed')
    report = {'runID': run_id, 'policy': args.policy, 'bundleID': bundle_id,
              'deviceUDID': args.device, 'candidateManifest': manifest,
              'unmodifiedExampleSources': source_hashes,
              'harnessSHA256': {test_source.name: digest(test_source), Path(__file__).name: digest(Path(__file__))},
              'pass': False}
    report_path = consumer / 'fallback-evidence.json'
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    try:
        with (consumer / 'prepare.log').open('w') as log:
            subprocess.run(['flutter', 'pub', 'get'], cwd=consumer, stdout=log,
                           stderr=subprocess.STDOUT, check=True, timeout=180)
        assert_package_origin(consumer, package, required_platforms=('ios',))
        report['pubspecLockSHA256'] = digest(consumer / 'pubspec.lock')
        report['resolvedDependencies'] = json.loads(subprocess.check_output(
            ['flutter', 'pub', 'deps', '--json'], cwd=consumer, text=True))
        with (consumer / 'build.log').open('w') as log:
            subprocess.run(['flutter', 'build', 'ios', '--simulator', '--debug', '--no-codesign'],
                           cwd=consumer, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=900)
        assert_package_origin(consumer, package, required_platforms=('ios',))
        verify_extracted(package, manifest)
        if example_source_hashes(consumer) != source_hashes:
            raise ValueError('Build changed the example Dart or Swift lifecycle source')
        command = [
            'xcodebuild', '-workspace', 'ios/Runner.xcworkspace', '-scheme', 'Runner',
            '-configuration', 'Debug', '-destination', f'platform=iOS Simulator,id={args.device}',
            '-derivedDataPath', str(consumer / 'fallback-derived'),
            '-resultBundlePath', str(consumer / 'fallback.xcresult'),
            '-only-testing:RunnerUITests/NotificationFallbackUITests/testPermissionAndRecovery',
            '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=NO', 'test',
        ]
        with (consumer / 'xcodebuild.log').open('w') as log:
            status = subprocess.run(command, cwd=consumer, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=900).returncode
        report['xcodebuildExitCode'] = status
        matches = re.findall(r'FALLBACK_EVIDENCE=(\{[^\n]+\})',
                             (consumer / 'xcodebuild.log').read_text())
        if status or len(matches) != 1:
            raise RuntimeError(f'Fallback UI test failed or lacked unique proof; exit={status}, records={len(matches)}')
        proof = json.loads(matches[0])
        report['observations'] = proof
        validate_observations(proof, bundle_id, args.policy)
        report['pass'] = True
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        final_error = None
        try:
            assert_package_origin(consumer, package, required_platforms=('ios',))
            verify_extracted(package, manifest)
            if example_source_hashes(consumer) != source_hashes:
                raise ValueError('Runtime changed the example Dart or Swift lifecycle source')
        except Exception as error:
            final_error = error
            report['pass'] = False
            report['verificationError'] = str(error)
        try:
            # The passing XCTest already stopped its app. This also handles a failed test.
            subprocess.run(['xcrun', 'simctl', 'terminate', args.device, bundle_id],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        except Exception as error:
            final_error = error
            report['pass'] = False
            report['cleanupError'] = str(error)
        finally:
            report_path.write_text(json.dumps(report, indent=2) + '\n')
            print(f'Fallback evidence: {report_path}', flush=True)
        if final_error:
            raise final_error
    print(json.dumps({'pass': report['pass'], 'policy': args.policy, 'bundleID': bundle_id}), flush=True)


if __name__ == '__main__':
    main()
