"""Reject desktop proof that reports acceptance without the required restarts."""
import copy
import unittest
from unittest.mock import patch

from run_desktop_proof import validate_proof, wait_for_only_final_process


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


if __name__ == '__main__':
    unittest.main()
