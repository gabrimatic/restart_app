"""Reject false macOS recovery claims and preserve the run-owned executable."""
import copy
from pathlib import Path
import tempfile
import unittest

from run_macos_recovery import fingerprint, restore_executable, validate_recovery


def fixture():
    capability = dict(fullProcessRestart=True, platformDefaultMode='process')
    commands = dict(fail='fail-command', old_ping='old-ping', retry='retry', new_ping='new-ping')

    def event(kind, pid, boot_id, timestamp, memory=0, **values):
        return dict(kind=kind, runId='owned-run', bootId=boot_id, pid=pid,
                    timestampMicros=timestamp, memory=memory, **values)

    initial = dict(runId='owned-run', bootId='first', pid=111, executable='/tmp/owned.app/Contents/MacOS/app',
                   bundle='/tmp/owned.app', events=[
        event('ready', 111, 'first', 1, capability=capability),
        event('fail_started', 111, 'first', 3, 4321, commandId=commands['fail']),
        event('fail_result', 111, 'first', 4, 4321, commandId=commands['fail'],
              success=False, mode='process', code='RESTART_FAILED', message='Executable missing'),
        event('failure_channel_alive', 111, 'first', 5, 4321,
              commandId=commands['fail'], capability=capability),
        event('ping', 111, 'first', 6, 4321, commandId=commands['old_ping'], capability=capability),
        event('retry_started', 111, 'first', 8, 4321, commandId=commands['retry']),
        event('retry_result', 111, 'first', 10, 4321, commandId=commands['retry'],
              success=True, mode='process', code=None),
    ])
    replacement = dict(runId='owned-run', bootId='second', pid=222,
                       executable=initial['executable'], bundle=initial['bundle'], events=[
        event('ready', 222, 'second', 9, capability=capability),
        event('ping', 222, 'second', 11, commandId=commands['new_ping'], capability=capability),
    ])
    original = dict(sha256='digest', size=123, mode=0o755)
    return dict(boots=[initial, replacement], run_id='owned-run', started_micros=1,
                initial_pid=111, executable=initial['executable'], copied_bundle=initial['bundle'],
                commands=commands, failure_window=dict(executable_absent=True,
                    initial_process_alive=True, boot_count=1),
                original_fingerprint=original, restored_fingerprint=copy.deepcopy(original),
                executable_removed_micros=2, restored_micros=7,
                old_process_exit_code=0, live_processes_before_cleanup=[222])


class MacOSRecoveryTest(unittest.TestCase):
    def test_complete_failure_restore_and_fresh_process_is_required(self):
        validate_recovery(fixture())
        corruptions = [
            lambda proof: proof['boots'][0]['events'][2].update(success=True),
            lambda proof: proof['boots'][0]['events'][2].update(code='RESTART_ALREADY_IN_PROGRESS'),
            lambda proof: proof['boots'][0]['events'][3].update(memory=0),
            lambda proof: proof['boots'][0]['events'].pop(4),
            lambda proof: proof['boots'][1].update(pid=111),
            lambda proof: proof['boots'][1].update(runId='stale-run'),
            lambda proof: proof['boots'][1].update(executable='/tmp/other.app/Contents/MacOS/app'),
            lambda proof: proof['boots'][1]['events'][0].update(memory=4321),
            lambda proof: proof['failure_window'].update(executable_absent=False),
            lambda proof: proof['failure_window'].update(initial_process_alive=False),
            lambda proof: proof['failure_window'].update(boot_count=2),
            lambda proof: proof['restored_fingerprint'].update(mode=0o644),
            lambda proof: proof.update(restored_micros=8),
            lambda proof: proof.update(executable_removed_micros=4),
            lambda proof: proof.update(old_process_exit_code=None),
            lambda proof: proof.update(live_processes_before_cleanup=[111, 222]),
        ]
        for index, corrupt in enumerate(corruptions):
            with self.subTest(case=index):
                proof = fixture()
                corrupt(proof)
                with self.assertRaises(RuntimeError):
                    validate_recovery(proof)

    def test_finally_restores_identical_bytes_and_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / 'owned-executable'
            backup = Path(directory) / 'owned-executable.unique-backup'
            executable.write_bytes(b'original executable\x00\xff')
            executable.chmod(0o751)
            original = fingerprint(executable)
            with self.assertRaisesRegex(RuntimeError, 'injected probe failure'):
                try:
                    executable.rename(backup)
                    raise RuntimeError('injected probe failure')
                finally:
                    restore_executable(executable, backup, original)
            self.assertEqual(fingerprint(executable), original)
            self.assertFalse(backup.exists())

    def test_restore_refuses_changed_backup_or_unexpected_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / 'owned-executable'
            backup = Path(directory) / 'owned-executable.unique-backup'
            executable.write_bytes(b'original')
            original = fingerprint(executable)
            executable.rename(backup)
            backup.write_bytes(b'changed')
            with self.assertRaisesRegex(RuntimeError, 'backup changed'):
                restore_executable(executable, backup, original)
            backup.write_bytes(b'original')
            executable.write_bytes(b'unexpected')
            with self.assertRaisesRegex(RuntimeError, 'unexpected executable'):
                restore_executable(executable, backup, original)
            self.assertEqual(executable.read_bytes(), b'unexpected')
            self.assertEqual(backup.read_bytes(), b'original')


if __name__ == '__main__':
    unittest.main()
