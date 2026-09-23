"""Reject desktop proof that reports acceptance without the required restarts."""
import copy
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from run_desktop_proof import main, validate_proof, wait_for_only_final_process


def fixture(cycles=30, platform='darwin'):
    pids = [700] * (cycles + 1) if platform == 'linux' else list(range(700, 701 + cycles))
    lines = ['requested_mode=flutterEngine', 'success=false', 'mode=flutterEngine',
             'code=UNSUPPORTED_RESTART_MODE',
             'requested_mode=notificationFallback', 'success=false', 'mode=notificationFallback',
             'code=UNSUPPORTED_RESTART_MODE']
    for cycle, pid in enumerate(pids):
        lines += [f'boot={cycle}', f'pid={pid}', 'startup_volatile=0',
                  f'persisted_launches={cycle}']
        if platform in ('linux', 'win32'):
            lines.append('arguments_preserved=true')
        if cycle < cycles:
            mode = 'platformDefault' if cycle % 2 == 0 else 'process'
            lines += [f'requested_mode={mode}', 'success=true', 'mode=process',
                      'duplicate_code=RESTART_ALREADY_IN_PROGRESS']
    if platform == 'linux':
        lines += ['linux_preflight_failure_recovered=true',
                  'linux_exec_failure_preserved_app=true']
    return dict(
        run_id='test-run', cycles=cycles, platform=platform,
        state=dict(runId='test-run', requestedCycles=cycles, complete=True,
                   cycle=cycles + 1, persistedLaunches=cycles + 1,
                   lastPid=str(pids[-1]), lastVolatileState=1000 + cycles),
        result='\n'.join(lines) + '\n',
        summary=f'RESTARTED_OK run_id=test-run requested_restarts={cycles} '
                f'launches={cycles + 1} restarts={cycles} state_reset=true '
                f'state_persisted=true concurrent_requests_rejected={cycles} '
                f'last_pid={pids[-1]} arguments_preserved=true '
                'deferred_failure_recovered=true',
        native_log='restart_app: execv failed; keeping current process alive',
    )


class DesktopProofTest(unittest.TestCase):
    def test_accepts_requested_count_on_each_platform(self):
        for platform in ('darwin', 'linux', 'win32'):
            for cycles in (1, 30):
                with self.subTest(platform=platform, cycles=cycles):
                    evidence = validate_proof(**fixture(cycles, platform))
                    self.assertEqual(evidence['requested_cycles'], cycles)
                    self.assertTrue(evidence['alternating_modes_verified'])

    def test_accepts_reused_historical_pid_after_an_intervening_process(self):
        for platform in ('darwin', 'win32'):
            with self.subTest(platform=platform):
                data = fixture(3, platform)
                data['result'] = data['result'].replace('pid=702\n', 'pid=700\n')
                self.assertEqual(validate_proof(**data)['boot_pids'],
                                 [700, 701, 700, 703])

    def test_rejects_unchanged_adjacent_pid_and_linux_pid_change(self):
        for platform in ('darwin', 'win32', 'linux'):
            with self.subTest(platform=platform):
                data = fixture(3, platform)
                old, new = ('700', '701') if platform == 'linux' else ('701', '700')
                data['result'] = data['result'].replace(f'pid={old}\n', f'pid={new}\n', 1)
                with self.assertRaisesRegex(RuntimeError, 'process identity'):
                    validate_proof(**data)

    def test_rejects_truncated_and_fabricated_results(self):
        original = fixture()
        corruptions = [
            ('result', 'boot=30\n', ''),
            ('result', 'startup_volatile=0', 'startup_volatile=9'),
            ('result', 'pid=701\n', 'pid=700\n'),
            ('result', 'requested_mode=platformDefault', 'requested_mode=process'),
            ('result', 'success=true', 'success=false'),
            ('result', 'mode=process\n', 'mode=process\nmode=unexpected\n'),
            ('result', 'duplicate_code=RESTART_ALREADY_IN_PROGRESS', 'duplicate_code='),
            ('result', 'code=UNSUPPORTED_RESTART_MODE', 'code='),
            ('summary', 'restarts=30 ', 'restarts=300 '),
        ]
        for field, old, new in corruptions:
            with self.subTest(field=field, old=old):
                data = copy.deepcopy(original)
                data[field] = data[field].replace(old, new, 1)
                with self.assertRaises(RuntimeError):
                    validate_proof(**data)

    def test_rejects_wrong_persisted_run_and_count(self):
        for key, value in [('runId', 'old-run'), ('requestedCycles', 10),
                           ('complete', False), ('cycle', 30),
                           ('persistedLaunches', 30), ('lastPid', '700')]:
            with self.subTest(key=key):
                data = fixture()
                data['state'][key] = value
                with self.assertRaises(RuntimeError):
                    validate_proof(**data)

    def test_linux_requires_native_failure_and_preserved_arguments(self):
        for field, token in [('native_log', 'execv failed'),
                             ('result', 'linux_exec_failure_preserved_app=true'),
                             ('result', 'linux_preflight_failure_recovered=true'),
                             ('result', 'arguments_preserved=true')]:
            with self.subTest(field=field, token=token):
                data = fixture(platform='linux')
                data[field] = data[field].replace(token, '', 1)
                with self.assertRaises(RuntimeError):
                    validate_proof(**data)

    def test_only_final_process_may_survive(self):
        with patch('run_desktop_proof.find_proof_processes', return_value={730}):
            self.assertEqual(wait_for_only_final_process(None, 730, timeout=0), [730])
        for survivors in ({729, 730}, set(), {999}):
            with self.subTest(survivors=survivors):
                with patch('run_desktop_proof.find_proof_processes', return_value=survivors):
                    with self.assertRaises(RuntimeError):
                        wait_for_only_final_process(None, 730, timeout=0)

    def test_run_retains_raw_evidence_and_only_passes_after_cleanup(self):
        for phase in ('validation', 'cleanup', 'launch', 'success'):
            with self.subTest(phase=phase), TemporaryDirectory() as temporary:
                home = Path(temporary)
                executable = home / 'proof.exe'
                executable.write_text('disposable executable fixture')
                output = home / 'proof.json'
                # A failed new run must not leave an earlier passing report.
                output.write_text('{"status": "passed"}')
                directory = home / 'restart_app_ci_proof'
                data = fixture(platform='win32')
                if phase == 'validation':
                    data['result'] = data['result'].replace('pid=701\n', 'pid=700\n')
                process = Mock(pid=700)
                process.poll.return_value = 0
                process.wait.return_value = 0

                def launch(*args, **kwargs):
                    self.assertEqual(json.loads(output.read_text())['status'],
                                     'not_yet_validated')
                    if phase == 'launch':
                        raise OSError('fixture launch failure')
                    directory.mkdir()
                    (directory / 'state.json').write_text(json.dumps(data['state']))
                    (directory / 'restart_result.txt').write_text(data['result'])
                    (directory / 'restart_proof.txt').write_text(data['summary'])
                    kwargs['stdout'].write('fixture native diagnostic\n')
                    kwargs['stdout'].flush()
                    return process

                def validate(**kwargs):
                    pending = json.loads(output.read_text())
                    self.assertEqual(pending['status'], 'not_yet_validated')
                    self.assertEqual(pending['raw_files'][str(directory)]['restart_result.txt'],
                                     data['result'])
                    return validate_proof(**kwargs)

                def cleanup(*args, **kwargs):
                    self.assertNotEqual(json.loads(output.read_text())['status'], 'passed')
                    if phase == 'cleanup':
                        for path in directory.iterdir():
                            path.unlink()
                        raise RuntimeError('fixture cleanup failure')
                    return False

                with patch('run_desktop_proof.Path.home', return_value=home), \
                        patch('run_desktop_proof.sys.platform', 'win32'), \
                        patch('run_desktop_proof.sys.argv',
                              ['proof', str(executable), '--output', str(output)]), \
                        patch('run_desktop_proof.uuid.uuid4', return_value=SimpleNamespace(hex='test-run')), \
                        patch('run_desktop_proof.find_proof_processes', return_value=set()), \
                        patch('run_desktop_proof.subprocess.Popen', side_effect=launch), \
                        patch('run_desktop_proof.validate_proof', side_effect=validate), \
                        patch('run_desktop_proof.wait_for_only_final_process', return_value=[730]), \
                        patch('run_desktop_proof.proof_process', side_effect=cleanup), \
                        patch('builtins.print'):
                    if phase == 'success':
                        main()
                    else:
                        with self.assertRaises((RuntimeError, OSError)):
                            main()
                failed = json.loads(output.read_text())
                self.assertEqual(failed['status'], 'passed' if phase == 'success' else 'failed')
                if phase != 'success':
                    self.assertEqual(failed['errors'][0]['phase'], phase)
                    self.assertNotIn('boot_pids', failed)
                    self.assertNotIn('summary', failed)
                else:
                    self.assertEqual(failed['boot_pids'], list(range(700, 731)))
                    self.assertEqual(failed['owned_processes_after_cleanup'], [])
                self.assertEqual(failed['cleanup_status'],
                                 'failed' if phase == 'cleanup' else 'passed')
                if phase != 'launch':
                    raw = failed['raw_files'][str(directory)]
                    self.assertEqual(raw['state.json'], json.dumps(data['state']))
                    self.assertEqual(raw['restart_result.txt'], data['result'])
                    self.assertEqual(raw['restart_proof.txt'], data['summary'])
                    self.assertEqual(failed['native_log'], 'fixture native diagnostic\n')


if __name__ == '__main__':
    unittest.main()
