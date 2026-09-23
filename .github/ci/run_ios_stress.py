#!/usr/bin/env python3
"""Run the prepared iOS consumer and collect lifecycle and memory evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import statistics
import subprocess

from candidate_package import assert_package_origin
from package_archive import inspect_archive, verify_extracted


MIB = 1024 * 1024


def positive_finite_number(value: object) -> bool:
    return (isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(value) and value > 0)


def _analyze(report: dict, expected: dict) -> dict:
    errors: list[str] = []
    investigations: list[str] = []
    memory_valid = True
    events = report['events']
    cycles = [event for event in events if event.get('kind') == 'cycle']
    count = expected['cycles']
    if report.get('configuration') != {
        key: expected[key] for key in [
            'runID', 'cycles', 'settleMilliseconds', 'archiveSHA256', 'resolvedPackageRoot'
        ]
    }:
        errors.append('Native configuration does not match the candidate manifest')
    if report.get('result', {}).get('pass') is not True:
        errors.append(f'App did not finish successfully: {report.get("result")}')
    if [event['cycle'] for event in cycles] != list(range(count + 1)):
        errors.append('Missing, duplicated, or reordered cycle records')
        memory_valid = False
    if len({event['boot'] for event in cycles}) != count + 1:
        errors.append('Fresh Dart boot identity was not proved for every cycle')
    if len({event['native']['pid'] for event in cycles}) != 1:
        errors.append('iOS process identity changed or is missing')
    for index, event in enumerate(cycles):
        native = event['native']
        if event['previousBoot'] != (cycles[index - 1]['boot'] if index else None):
            errors.append(f'Broken persistence chain at cycle {event["cycle"]}')
        if (native['memoryStatus'] != 0 or not positive_finite_number(native['residentBytes'])
                or not positive_finite_number(native['physFootprintBytes'])):
            errors.append(f'Native memory sample failed at cycle {event["cycle"]}')
            memory_valid = False
        if (native['oldUndestroyedEngines'] != 0 or
                native['destructionRequests'] != event['cycle'] or
                native['destructionCompletions'] != event['cycle'] or
                native['enginesCreated'] != event['cycle'] + 1 or
                native['currentEngineID'] != event['cycle'] + 1):
            errors.append(f'Engine lifecycle mismatch at cycle {event["cycle"]}')
        expected_clicks = 2 if event['cycle'] > 0 and event['cycle'] % 10 == 0 else 1
        if (event['dirty'] != 0 or event['webViewClicks'] != expected_clicks or
                not math.isfinite(event['webViewScrollY']) or
                abs(event['webViewScrollY'] - expected_clicks * 120) > 2 or
                not isinstance(event['webViewStableFrames'], int) or
                event['webViewStableFrames'] < 3 or
                not positive_finite_number(event['webViewStabilizationMilliseconds']) or
                event['webViewStabilizationMilliseconds'] > 2000 or
                not math.isfinite(event['webViewSettledScrollY']) or
                abs(event['webViewSettledScrollY'] - expected_clicks * 120) > 2):
            errors.append(f'Dart state or WebView failed at cycle {event["cycle"]}')
    checkpoints = list(range(10, count + 1, 10))
    lifecycle = [event for event in events if event.get('kind') == 'lifecycle']
    if [event['cycle'] for event in lifecycle] != checkpoints:
        errors.append('Missing real Home/activate checkpoints')
    for event in lifecycle:
        states = event.get('states', [])
        if 'paused' not in states or 'resumed' not in states[states.index('paused') + 1:]:
            errors.append(f'No pause/resume lifecycle pair at cycle {event["cycle"]}')
    rejections = [event['cycle'] for event in events if event.get('kind') == 'process-rejected']
    if rejections != checkpoints:
        errors.append('Missing unsupported process-mode rejections')
    for kind in ['request', 'accepted']:
        requests = [event for event in events if event.get('kind') == kind]
        if [event['cycle'] for event in requests] != list(range(count)):
            errors.append(f'Missing or duplicated {kind} restart records')
        for event in requests:
            requested_mode = 'platformDefault' if event['cycle'] % 2 == 0 else 'flutterEngine'
            if event['requestedMode'] != requested_mode:
                errors.append(f'Wrong requested mode at cycle {event["cycle"]}')
            if kind == 'accepted' and (event['success'] is not True or event['resolvedMode'] != 'flutterEngine'):
                errors.append(f'Wrong returned mode/result at cycle {event["cycle"]}')

    warmup = 10 if count >= 100 else 5
    block_size = 10 if count >= 100 else 5
    final_size = 20 if count >= 100 else 10
    settled = [event for event in cycles if event['cycle'] > warmup]
    memory = {}
    for field in ['residentBytes', 'physFootprintBytes']:
        values = [event['native'][field] for event in settled]
        if not all(positive_finite_number(value) for value in values):
            memory_valid = False
            continue
        if len(values) < 2 * block_size:
            errors.append('Not enough settled cycles for the memory comparison')
            memory_valid = False
            continue
        early = statistics.median(values[:block_size])
        final = statistics.median(values[-final_size:])
        blocks = [statistics.median(values[offset:offset + block_size])
                  for offset in range(0, len(values) - block_size + 1, block_size)]
        last = blocks[-3:]
        slope = (last[-1] - last[0]) / (block_size * (len(last) - 1)) if len(last) > 1 else 0
        monotonic = len(last) >= 3 and all(right > left for left, right in zip(last, last[1:]))
        delta = final - early
        memory[field] = {
            'warmupCycles': warmup, 'blockSize': block_size,
            'earlyCycles': [warmup + 1, warmup + block_size],
            'finalCycles': [count - final_size + 1, count],
            'earlyMedian': early, 'finalMedian': final, 'medianGrowth': delta,
            'growthThreshold': max(30 * MIB, early * 0.20),
            'blockMedians': blocks, 'finalBlockSlopeBytesPerCycle': slope,
            'continuingMonotonicGrowth': monotonic,
        }
        if delta > max(30 * MIB, early * 0.20) or monotonic:
            investigations.append(f'{field} grows beyond the steady-state gate')
    if settled:
        for field in ['liveEngineWrappers', 'liveControllers', 'liveWebViews']:
            baseline = max(event['native'][field] for event in settled[:block_size])
            peak = max(event['native'][field] for event in settled)
            memory[field] = {'initialSettledBaseline': baseline, 'settledPeak': peak}
            if peak > baseline:
                investigations.append(f'{field} grows beyond its settled baseline')
        retained = sorted({identity for event in settled
                           for identity in event['native']['retainedDestroyedEngineIDs']})
        memory['retainedDestroyedEngineIDs'] = retained
        if any(identity != 1 for identity in retained):
            investigations.append('A replacement engine wrapper remains retained after settling')
        for field in ['oldLiveControllerIDs', 'oldLiveWebViewIDs']:
            retained_views = sorted({identity for event in settled
                                     for identity in event['native'][field]})
            memory[field] = retained_views
            if any(identity != 1 for identity in retained_views):
                investigations.append(f'A replacement view remains retained: {field}')
    network = [event for event in events if event.get('kind') == 'network']
    network_pass = ([event['cycle'] for event in network] == [0, count]
                    and all(event.get('pass') is True for event in network))
    return {
        'restartPassed': not errors,
        'networkSmokePassed': network_pass,
        'memoryPassed': memory_valid and not investigations,
        'errors': errors, 'investigations': investigations, 'memory': memory,
        'pass': not errors and not investigations and network_pass,
    }


def analyze(report: dict, expected: dict) -> dict:
    try:
        return _analyze(report, expected)
    except (KeyError, TypeError, ValueError, IndexError, AttributeError) as error:
        return {
            'restartPassed': False, 'networkSmokePassed': False,
            'memoryPassed': False, 'pass': False, 'investigations': [],
            'memory': {}, 'errors': [f'Malformed or missing evidence: {error}'],
        }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('consumer', type=Path)
    parser.add_argument('--device', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--collect-only', action='store_true')
    args = parser.parse_args()
    consumer = args.consumer.resolve()
    expected = json.loads((consumer / 'stress-config.json').read_text())
    if hashlib.sha256(Path(expected['archive']).read_bytes()).hexdigest() != expected['archiveSHA256']:
        raise RuntimeError('Candidate archive changed after consumer preparation')
    package = Path(expected['resolvedPackageRoot'])
    payload_manifest = inspect_archive(Path(expected['archive']))
    stored_manifest = json.loads((consumer / 'stress-package-manifest.json').read_text())
    if stored_manifest != payload_manifest:
        raise RuntimeError('Stored candidate payload manifest differs from the archive')
    if payload_manifest['payloadSha256'] != expected['payloadSHA256']:
        raise RuntimeError('Candidate payload manifest changed after preparation')
    assert_package_origin(consumer, package, required_platforms=('ios',))
    verify_extracted(package, payload_manifest)
    output = args.output.resolve()
    if output.exists():
        raise RuntimeError(f'Refusing to overwrite evidence: {output}')
    output.parent.mkdir(parents=True, exist_ok=True)
    build_status = None
    if not args.collect_only:
        build_log = output.with_suffix('.build.log')
        with build_log.open('w') as log:
            build_status = subprocess.run(
                ['flutter', 'build', 'ios', '--simulator', '--debug', '--no-codesign'],
                cwd=consumer, stdout=log, stderr=subprocess.STDOUT,
            ).returncode
        if build_status:
            raise RuntimeError(f'Consumer build failed; see {build_log}')
        assert_package_origin(consumer, package, required_platforms=('ios',))
        verify_extracted(package, payload_manifest)
        test_log = output.with_suffix('.xcodebuild.log')
        with test_log.open('w') as log:
            build_status = subprocess.run([
                'xcodebuild', '-workspace', 'ios/Runner.xcworkspace', '-scheme', 'Runner',
                '-configuration', 'Debug', '-destination', f'platform=iOS Simulator,id={args.device}',
                '-derivedDataPath', str(consumer / 'stress-derived'),
                '-resultBundlePath', str(output.with_suffix('.xcresult')),
                '-only-testing:RunnerUITests/RestartStressUITests/testRepeatedEngineRestartsAndHomeResume',
                '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=NO', 'test',
            ], cwd=consumer, stdout=log, stderr=subprocess.STDOUT).returncode
    assert_package_origin(consumer, package, required_platforms=('ios',))
    verify_extracted(package, payload_manifest)
    try:
        container = Path(subprocess.check_output([
            'xcrun', 'simctl', 'get_app_container', args.device, expected['bundleID'], 'data',
        ], text=True, stderr=subprocess.PIPE).strip())
        report = json.loads((container / 'Documents/restart-stress.json').read_text())
        report['events'] = [json.loads(line) for line in
                            (container / 'Documents/restart-stress-events.jsonl').read_text().splitlines()
                            if line and json.loads(line).get('runID') == expected['runID']]
    except (subprocess.CalledProcessError, OSError, json.JSONDecodeError) as error:
        report = {
            'events': [],
            'result': {'pass': False, 'error': f'App evidence unavailable: {error}'},
        }
    report['candidateManifest'] = expected
    report['resolvedDependencies'] = json.loads((consumer / 'stress-dependencies.json').read_text())
    report['xcodebuildExitCode'] = build_status
    report['deviceUDID'] = args.device
    report['analysis'] = analyze(report, expected)
    if build_status is None:
        report['analysis']['pass'] = False
        report['analysis']['verificationIncomplete'] = True
        report['analysis']['errors'].append('Collection-only report has no verified XCUITest exit status')
    elif build_status:
        report['analysis']['pass'] = False
        report['analysis']['errors'].append(f'XCUITest exited {build_status}')
    output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report['analysis'], indent=2))
    print(f'Evidence: {output}')
    if not report['analysis']['pass']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
