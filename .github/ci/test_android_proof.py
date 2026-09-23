"""Adversarial checks for Android boot, mode, UI and lifecycle evidence."""
import unittest
import json
from pathlib import Path
import shlex
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from run_android_proof import KINDS, PACKAGE, control_file_script, page_size_evidence, private_file_script, ui_texts, validate_summary, verify_lifecycle


def summary(cycles=30):
    history, requests = [], []
    pid = 2000
    for cycle in range(cycles + 1):
        history.append(dict(cycle=cycle, boot=str(10000 + cycle), pid=pid, dirty=0))
        if cycle < cycles:
            kind = KINDS[cycle % 3]
            requests.append(dict(cycle=cycle, kind=kind,
                                 mode='process' if kind == 'process' else 'platformDefault',
                                 forceKill=kind == 'forceKill',
                                 resolvedMode='platformDefault' if kind == 'platformDefault' else 'process',
                                 duplicatesRejected=8, unsupportedRejected=2))
            if kind != 'platformDefault':
                pid += 1
    return dict(runId='fresh-run', requestedCycles=cycles, complete=True,
                finalPid=pid, finalBoot=history[-1]['boot'], history=history, requests=requests)


class AndroidProofTest(unittest.TestCase):
    def test_page_size_is_measured_numeric_data_or_explicitly_unavailable(self):
        self.assertEqual(page_size_evidence('16384\r\n'), {'page_size': 16384})
        for output in ['/system/bin/sh: getconf: not found', '0', 'unknown', '']:
            result = page_size_evidence(output)
            self.assertIsNone(result['page_size'])
            self.assertTrue(result['page_size_error'])

    def test_absent_failure_file_has_no_error_text_with_zero_exit_status(self):
        with tempfile.TemporaryDirectory(prefix='restart_read_') as temporary:
            root = Path(temporary)
            (root / 'files').mkdir()
            script = private_file_script('failure.json')
            self.assertEqual(subprocess.check_output(['sh', '-c', script], cwd=root), b'')
            (root / 'files/restart-proof-failure.json').write_text('{"error":"actual app error"}')
            self.assertEqual(subprocess.check_output(['sh', '-c', script], cwd=root),
                             b'{"error":"actual app error"}')
        with self.assertRaises(ValueError):
            private_file_script('../../unexpected')

    def test_control_payload_is_literal_through_both_shell_layers(self):
        payload = dict(runId="quote' double\" $(touch injected) `touch injected`\nRESTART_PROOF_JSON\nback\\slash café 東京",
                       cycle=30, action='complete')
        with tempfile.TemporaryDirectory(prefix='restart_control_') as temporary:
            root = Path(temporary)
            (root / 'files').mkdir()
            script = control_file_script('command', payload)
            subprocess.run(['sh', '-c', f'sh -c {shlex.quote(script)}'], cwd=root, check=True)
            self.assertEqual(json.loads((root / 'files/restart-proof-command.json').read_text()), payload)
            self.assertFalse((root / 'injected').exists())
            self.assertFalse((root / 'files/restart-proof-command.tmp').exists())
        with self.assertRaises(ValueError):
            control_file_script('../../unexpected', payload)

    def test_flutter_semantics_content_description(self):
        hierarchy = ET.fromstring(f'''<hierarchy><node text="" content-desc="">
          <node package="{PACKAGE}" text="" content-desc="PASS 30 Android restarts" />
        </node></hierarchy>''')
        self.assertEqual(ui_texts(hierarchy), ['PASS 30 Android restarts'])

    def test_native_text_and_duplicate_accessibility_labels(self):
        hierarchy = ET.fromstring(f'''<hierarchy>
          <node package="{PACKAGE}" text="FAIL restart did not complete" content-desc="" />
          <node package="{PACKAGE}" text="" content-desc="FAIL restart did not complete" />
          <node package="another.app" text="PASS 60 Android restarts" />
          <node text="" />
        </hierarchy>''')
        self.assertEqual(ui_texts(hierarchy), ['FAIL restart did not complete'])

    def test_exact_mode_counts_and_fresh_boots_for_both_api_gates(self):
        for cycles in (30, 60):
            evidence = validate_summary(summary(cycles), 'fresh-run', cycles, 10000)
            self.assertEqual(evidence['mode_counts'], {kind: cycles // 3 for kind in KINDS})
            self.assertEqual(evidence['fresh_restart_boots'], cycles + 1)
            self.assertEqual(evidence['duplicate_requests_rejected'], cycles * 8)

    def test_stale_run_or_boot_cannot_satisfy_proof(self):
        for run_id, start in [('old-run', 10000), ('fresh-run', 10001)]:
            with self.assertRaises(RuntimeError):
                validate_summary(summary(), run_id, 30, start)

    def test_rejects_corrupt_counter_mode_results_and_process_identity(self):
        corruptions = [
            ('history', 3, 'cycle', 2), ('history', 2, 'boot', '10001'),
            ('history', 2, 'pid', 2000), ('history', 5, 'dirty', 137),
            ('requests', 0, 'kind', 'process'), ('requests', 1, 'mode', 'platformDefault'),
            ('requests', 2, 'forceKill', False), ('requests', 2, 'resolvedMode', 'platformDefault'),
            ('requests', 5, 'duplicatesRejected', 7), ('requests', 5, 'unsupportedRejected', 1),
        ]
        for collection, index, key, value in corruptions:
            with self.subTest(collection=collection, index=index, key=key):
                data = summary()
                data[collection][index][key] = value
                with self.assertRaises(RuntimeError):
                    validate_summary(data, 'fresh-run', 30, 10000)
        data = summary()
        data['history'].pop()
        with self.assertRaisesRegex(RuntimeError, 'Incomplete'):
            validate_summary(data, 'fresh-run', 30, 10000)

    def test_home_resume_requires_both_native_and_dart_lifecycle(self):
        before = dict(cycle=5, pid=2000, activity='activity-a', boot='10005', dirty=0)
        native = [dict(event=event, activity='activity-a') for event in ('onPause', 'onResume')]
        dart = [dict(event='lifecycle', boot='10005', state=state) for state in ('paused', 'resumed')]
        verify_lifecycle(before, before, native, dart, rotation=False)
        hidden_only = [dict(event='lifecycle', boot='10005', state=state)
                       for state in ('hidden', 'resumed')]
        for events, dart_events in [(native[:1], dart), (native, dart[:1]), (native, []),
                                    (list(reversed(native)), dart), (native, list(reversed(dart))),
                                    (native, hidden_only)]:
            with self.assertRaises(RuntimeError):
                verify_lifecycle(before, before, events, dart_events, rotation=False)
        changed = dict(before, boot='10006')
        with self.assertRaises(RuntimeError):
            verify_lifecycle(before, changed, native, dart, rotation=False)

    def test_rotation_requires_activity_destroy_create_and_new_dart_boot(self):
        before = dict(cycle=10, pid=2000, activity='activity-a', boot='10010', dirty=0)
        after = dict(before, activity='activity-b', boot='10011', kind='rotation')
        native = [dict(event='onDestroy', activity='activity-a'), dict(event='onCreate', activity='activity-b')]
        dart = [dict(event='boot', boot='10011', kind='rotation')]
        verify_lifecycle(before, after, native, dart, rotation=True)
        for field, value in [('activity', 'activity-a'), ('boot', '10010'), ('cycle', 11), ('pid', 2001)]:
            with self.subTest(field=field):
                changed = dict(after, **{field: value})
                with self.assertRaises(RuntimeError):
                    verify_lifecycle(before, changed, native, dart, rotation=True)
        for events, dart_events in [(native[:1], dart), (native[1:], dart), (native, []),
                                    (list(reversed(native)), dart)]:
            with self.assertRaises(RuntimeError):
                verify_lifecycle(before, after, events, dart_events, rotation=True)


if __name__ == '__main__':
    unittest.main()
