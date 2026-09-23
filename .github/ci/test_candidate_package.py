"""Guard against package tests silently resolving an old working checkout."""

import json
from pathlib import Path
import tempfile
import unittest

from candidate_package import (
    assert_package_origin,
    assert_package_version,
    package_directory,
    resolved_package_directory,
)


class CandidatePackageTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='restart_candidate_test_')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.candidate = self.root / 'candidate with spaces ü'
        self.candidate.mkdir()
        (self.candidate / 'pubspec.yaml').write_text('name: restart_app\nversion: 1.10.0\n')
        self.consumer = self.root / 'consumer'
        (self.consumer / '.dart_tool').mkdir(parents=True)
        self.write_config(self.candidate.as_uri())
        self.write_plugins(self.candidate)

    def write_config(self, root_uri):
        (self.consumer / '.dart_tool/package_config.json').write_text(json.dumps({
            'configVersion': 2,
            'packages': [{'name': 'restart_app', 'rootUri': root_uri}],
        }))

    def write_plugins(self, package):
        (self.consumer / '.flutter-plugins-dependencies').write_text(json.dumps({
            'plugins': {'android': [{'name': 'restart_app', 'path': str(package)}]},
        }))

    def test_absolute_uri_with_encoded_spaces_and_unicode(self):
        self.assertEqual(resolved_package_directory(self.consumer), self.candidate)
        assert_package_origin(self.consumer, self.candidate, required_platforms=('android',))

    def test_relative_uri_resolves_from_package_config(self):
        self.write_config('../../candidate%20with%20spaces%20%C3%BC/')
        self.assertEqual(resolved_package_directory(self.consumer), self.candidate)

    def test_other_package_is_rejected(self):
        (self.candidate / 'pubspec.yaml').write_text('name: another_package\n# name: restart_app\n')
        with self.assertRaisesRegex(ValueError, 'not restart_app'):
            package_directory(self.candidate)

    def test_stale_dart_resolution_is_rejected(self):
        checkout = self.root / 'working_checkout'
        checkout.mkdir()
        (checkout / 'pubspec.yaml').write_text('name: restart_app\n')
        self.write_config(checkout.as_uri())
        with self.assertRaisesRegex(RuntimeError, 'resolved to'):
            assert_package_origin(self.consumer, self.candidate)

    def test_stale_native_resolution_is_rejected(self):
        self.write_plugins(self.root / 'working_checkout')
        with self.assertRaisesRegex(RuntimeError, 'android restart_app plugin uses'):
            assert_package_origin(self.consumer, self.candidate)

    def test_missing_required_native_platform_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'Missing restart_app plugin platforms'):
            assert_package_origin(self.consumer, self.candidate, required_platforms=('ios',))

    def test_missing_plugin_metadata_is_rejected(self):
        (self.consumer / '.flutter-plugins-dependencies').unlink()
        with self.assertRaisesRegex(RuntimeError, 'Missing Flutter plugin metadata'):
            assert_package_origin(self.consumer, self.candidate)

    def test_dart_only_fixture_can_explicitly_omit_native_metadata(self):
        (self.consumer / '.flutter-plugins-dependencies').unlink()
        assert_package_origin(self.consumer, self.candidate, require_native_metadata=False)

    def test_dart_only_fixture_still_checks_existing_native_metadata(self):
        self.write_plugins(self.root / 'working_checkout')
        with self.assertRaisesRegex(RuntimeError, 'android restart_app plugin uses'):
            assert_package_origin(self.consumer, self.candidate, require_native_metadata=False)

    def test_required_native_platforms_cannot_bypass_metadata(self):
        with self.assertRaisesRegex(ValueError, 'cannot omit native metadata'):
            assert_package_origin(self.consumer, self.candidate,
                                  required_platforms=('ios',), require_native_metadata=False)

    def test_duplicate_resolved_packages_are_rejected(self):
        config = self.consumer / '.dart_tool/package_config.json'
        data = json.loads(config.read_text())
        data['packages'].append(data['packages'][0])
        config.write_text(json.dumps(data))
        with self.assertRaisesRegex(RuntimeError, 'exactly one'):
            resolved_package_directory(self.consumer)

    def test_unexpected_uri_scheme_is_rejected(self):
        self.write_config('https://example.com/restart_app')
        with self.assertRaisesRegex(RuntimeError, 'Unexpected restart_app package URI'):
            resolved_package_directory(self.consumer)

    def test_requested_version_is_checked_exactly(self):
        assert_package_version(self.candidate, '1.10.0')
        with self.assertRaisesRegex(RuntimeError, 'requested version 1.9.2'):
            assert_package_version(self.candidate, '1.9.2')


if __name__ == '__main__':
    unittest.main()
