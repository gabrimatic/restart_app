import copy
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest import mock

from package_archive import inspect_archive
from run_ios_stress import analyze, main


def proof():
    config = {
        'runID': 'fixture', 'cycles': 30, 'settleMilliseconds': 2000,
        'archiveSHA256': 'a' * 64, 'resolvedPackageRoot': '/tmp/candidate',
    }
    events = []
    for cycle in range(31):
        if cycle in (0, 30):
            events.append({'kind': 'network', 'cycle': cycle, 'pass': True})
        if cycle and cycle % 10 == 0:
            events.extend([
                {'kind': 'process-rejected', 'cycle': cycle},
                {'kind': 'lifecycle', 'cycle': cycle, 'states': ['inactive', 'paused', 'resumed']},
            ])
        events.append({
            'kind': 'cycle', 'cycle': cycle, 'boot': f'boot-{cycle}',
            'previousBoot': f'boot-{cycle - 1}' if cycle else None,
            'dirty': 0, 'webViewClicks': 2 if cycle and cycle % 10 == 0 else 1,
            'webViewScrollY': 240 if cycle and cycle % 10 == 0 else 120,
            'webViewStableFrames': 3,
            'webViewStabilizationMilliseconds': 50,
            'webViewSettledScrollY': 240 if cycle and cycle % 10 == 0 else 120,
            'native': {
                'pid': 42, 'memoryStatus': 0,
                'residentBytes': 150 * 1024 * 1024,
                'physFootprintBytes': 120 * 1024 * 1024,
                'oldUndestroyedEngines': 0,
                'destructionRequests': cycle, 'destructionCompletions': cycle,
                'enginesCreated': cycle + 1,
                'currentEngineID': cycle + 1,
                'liveEngineWrappers': 2 if cycle else 1,
                'liveControllers': 1, 'liveWebViews': 1,
                'retainedDestroyedEngineIDs': [1] if cycle else [],
                'oldLiveControllerIDs': [], 'oldLiveWebViewIDs': [],
            },
        })
        if cycle < 30:
            for kind in ['request', 'accepted']:
                events.append({
                    'kind': kind, 'cycle': cycle,
                    'requestedMode': 'platformDefault' if cycle % 2 == 0 else 'flutterEngine',
                    'resolvedMode': 'flutterEngine', 'success': True,
                })
    return {'configuration': copy.deepcopy(config), 'result': {'pass': True}, 'events': events}, config


class IOSStressEvidenceTests(unittest.TestCase):
    def test_complete_stable_run_passes(self):
        report, config = proof()
        self.assertTrue(analyze(report, config)['pass'])

    def test_duplicate_boot_cannot_be_a_restart(self):
        report, config = proof()
        report['events'][-1]['boot'] = 'boot-29'
        self.assertFalse(analyze(report, config)['restartPassed'])

    def test_process_relaunch_cannot_count_as_engine_restart(self):
        report, config = proof()
        report['events'][-1]['native']['pid'] = 43
        self.assertFalse(analyze(report, config)['restartPassed'])

    def test_missing_destruction_completion_fails(self):
        report, config = proof()
        report['events'][-1]['native']['destructionCompletions'] = 29
        self.assertFalse(analyze(report, config)['restartPassed'])

    def test_retained_replacement_requires_investigation(self):
        report, config = proof()
        report['events'][-1]['native']['retainedDestroyedEngineIDs'] = [1, 8]
        self.assertFalse(analyze(report, config)['memoryPassed'])

    def test_small_continuing_memory_growth_requires_investigation(self):
        report, config = proof()
        for event in report['events']:
            if event['kind'] == 'cycle':
                event['native']['residentBytes'] += event['cycle'] * 100 * 1024
        self.assertFalse(analyze(report, config)['memoryPassed'])

    def test_network_failure_is_separate_from_restart_identity(self):
        report, config = proof()
        report['events'][0]['pass'] = False
        result = analyze(report, config)
        self.assertTrue(result['restartPassed'])
        self.assertFalse(result['networkSmokePassed'])
        self.assertFalse(result['pass'])

    def test_missing_background_transition_fails(self):
        report, config = proof()
        event = next(event for event in report['events'] if event['kind'] == 'lifecycle')
        event['states'] = ['inactive', 'resumed']
        self.assertFalse(analyze(report, config)['restartPassed'])

    def test_missing_or_stale_webview_scroll_fails(self):
        for offset in [None, 0, 120, 243, float('nan'), float('inf')]:
            report, config = proof()
            report['events'][-1]['webViewScrollY'] = offset
            self.assertFalse(analyze(report, config)['restartPassed'])

    def test_missing_post_resume_webview_action_fails(self):
        report, config = proof()
        report['events'][-1]['webViewClicks'] = 1
        self.assertFalse(analyze(report, config)['restartPassed'])

    def test_scroll_must_stabilize_and_remain_after_settling(self):
        for field, value in [('webViewStableFrames', 2),
                             ('webViewStableFrames', None),
                             ('webViewStableFrames', float('nan')),
                             ('webViewStabilizationMilliseconds', 2001),
                             ('webViewSettledScrollY', 0),
                             ('webViewSettledScrollY', 120),
                             ('webViewSettledScrollY', float('nan'))]:
            report, config = proof()
            report['events'][-1][field] = value
            self.assertFalse(analyze(report, config)['restartPassed'])

    def test_malformed_and_missing_events_fail_cleanly(self):
        for malformed in [None, {}, [], ['bad'], [{'kind': 'cycle'}]]:
            report, config = proof()
            report['events'] = malformed
            self.assertFalse(analyze(report, config)['pass'])

    def test_missing_native_identity_and_zero_footprint_fail(self):
        for field in ['currentEngineID', 'physFootprintBytes']:
            report, config = proof()
            report['events'][-1]['native'][field] = 0
            self.assertFalse(analyze(report, config)['restartPassed'])

    def test_nonnumeric_or_nonfinite_memory_cannot_pass(self):
        for field in ['residentBytes', 'physFootprintBytes']:
            for value in [None, 'not a number', False, 0, -1, float('nan'), float('inf')]:
                with self.subTest(field=field, value=value):
                    report, config = proof()
                    report['events'][-1]['native'][field] = value
                    result = analyze(report, config)
                    self.assertFalse(result['pass'])
                    self.assertFalse(result['memoryPassed'])

    def test_partial_run_cannot_claim_the_requested_final_memory_window(self):
        report, config = proof()
        report['events'] = [event for event in report['events']
                            if event.get('cycle', 0) < 20]
        result = analyze(report, config)
        self.assertFalse(result['pass'])
        self.assertFalse(result['memoryPassed'])

    def test_returned_restart_mode_is_verified(self):
        report, config = proof()
        accepted = next(event for event in report['events'] if event['kind'] == 'accepted')
        accepted['resolvedMode'] = 'process'
        self.assertFalse(analyze(report, config)['restartPassed'])

    def test_request_counts_are_verified(self):
        report, config = proof()
        report['events'] = [event for event in report['events'] if event['kind'] != 'request']
        self.assertFalse(analyze(report, config)['restartPassed'])

    def _collector_fixture(self, root):
        consumer = root / 'consumer'
        package = consumer / 'candidate_package'
        package.mkdir(parents=True)
        (package / 'payload.txt').write_text('immutable candidate')
        archive = root / 'candidate.tar.gz'
        with tarfile.open(archive, 'w:gz') as bundle:
            bundle.add(package / 'payload.txt', arcname='payload.txt')
        manifest = inspect_archive(archive)
        report, config = proof()
        config.update(
            archive=str(archive), archiveSHA256=manifest['archiveSha256'],
            resolvedPackageRoot=str(package), payloadSHA256=manifest['payloadSha256'],
            bundleID='info.gabrimatic.restartapp.stress',
        )
        report['configuration'] = {key: config[key] for key in report['configuration']}
        (consumer / 'stress-config.json').write_text(json.dumps(config))
        (consumer / 'stress-package-manifest.json').write_text(json.dumps(manifest))
        (consumer / 'stress-dependencies.json').write_text('{}')
        data = root / 'app-data'
        documents = data / 'Documents'
        documents.mkdir(parents=True)
        (documents / 'restart-stress.json').write_text(json.dumps(report))
        (documents / 'restart-stress-events.jsonl').write_text('\n'.join(
            json.dumps(dict(event, runID=config['runID'])) for event in report['events']))
        return consumer, data

    def test_collection_only_cannot_pass_without_a_real_xctest_result(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            consumer, data = self._collector_fixture(root)
            output = root / 'report.json'
            arguments = ['run_ios_stress.py', str(consumer), '--device', 'fixture-device',
                         '--output', str(output), '--collect-only']
            with (mock.patch('sys.argv', arguments),
                  mock.patch('run_ios_stress.assert_package_origin'),
                  mock.patch('run_ios_stress.subprocess.check_output', return_value=f'{data}\n'),
                  mock.patch('builtins.print')):
                with self.assertRaises(SystemExit):
                    main()
            result = json.loads(output.read_text())
            self.assertIsNone(result['xcodebuildExitCode'])
            self.assertTrue(result['analysis']['restartPassed'])
            self.assertTrue(result['analysis']['memoryPassed'])
            self.assertFalse(result['analysis']['pass'])
            self.assertTrue(result['analysis']['verificationIncomplete'])

    def test_failed_xctest_without_app_artifacts_still_writes_failed_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            consumer, _ = self._collector_fixture(root)
            output = root / 'report.json'
            arguments = ['run_ios_stress.py', str(consumer), '--device', 'fixture-device',
                         '--output', str(output)]
            with (mock.patch('sys.argv', arguments),
                  mock.patch('run_ios_stress.assert_package_origin'),
                  mock.patch('run_ios_stress.subprocess.run', side_effect=[
                      subprocess.CompletedProcess([], 0), subprocess.CompletedProcess([], 65)]),
                  mock.patch('run_ios_stress.subprocess.check_output',
                             side_effect=subprocess.CalledProcessError(2, 'simctl')),
                  mock.patch('builtins.print')):
                with self.assertRaises(SystemExit):
                    main()
            result = json.loads(output.read_text())
            self.assertEqual(result['xcodebuildExitCode'], 65)
            self.assertFalse(result['analysis']['restartPassed'])
            self.assertFalse(result['analysis']['memoryPassed'])
            self.assertFalse(result['analysis']['pass'])
            self.assertIn('App evidence unavailable', result['result']['error'])


if __name__ == '__main__':
    unittest.main()
