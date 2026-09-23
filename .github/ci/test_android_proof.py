"""Regression coverage for the UI hierarchy returned by real Android probes."""
import unittest
import xml.etree.ElementTree as ET

from run_android_proof import PACKAGE, proof_records, ui_texts


class AndroidProofTextTest(unittest.TestCase):
    def test_flutter_semantics_content_description(self):
        # Flutter Text exposes content-desc on both API 21 and API 37.
        hierarchy = ET.fromstring(f'''<hierarchy><node text="" content-desc="">
          <node package="{PACKAGE}" text="" content-desc="PASS 15 Android restarts&#10;cycle=0 boot=123 pid=456 dirty=0" />
        </node></hierarchy>''')
        self.assertEqual(ui_texts(hierarchy), [
            'PASS 15 Android restarts\ncycle=0 boot=123 pid=456 dirty=0'
        ])

    def test_native_text_and_duplicate_accessibility_labels(self):
        hierarchy = ET.fromstring(f'''<hierarchy>
          <node package="{PACKAGE}" text="FAIL restart did not complete" content-desc="" />
          <node package="{PACKAGE}" text="" content-desc="FAIL restart did not complete" />
          <node package="another.app" text="PASS 15 Android restarts" />
          <node text="" />
        </hierarchy>''')
        self.assertEqual(ui_texts(hierarchy), ['FAIL restart did not complete'])

    def test_old_pass_does_not_satisfy_a_new_run(self):
        history = '\n'.join(
            f'cycle={cycle} boot={1000 + cycle} pid={2000 + cycle} dirty=0'
            for cycle in range(16)
        )
        self.assertIsNone(proof_records(history, started_us=2000))
        self.assertEqual(len(proof_records(history, started_us=1000)), 16)

    def test_fresh_incomplete_history_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'Incomplete launch history'):
            proof_records('cycle=0 boot=1000 pid=2000 dirty=0', started_us=1000)


if __name__ == '__main__':
    unittest.main()
