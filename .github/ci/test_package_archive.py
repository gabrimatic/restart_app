import io
import os
from pathlib import Path
import tarfile
import tempfile
import unittest

from package_archive import inspect_archive, verify_extracted


class PackageArchiveTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def archive(self, name, entries, mtime=0):
        path = self.root / name
        with tarfile.open(path, 'w:gz') as bundle:
            for filename, content, mode in entries:
                info = tarfile.TarInfo(filename)
                info.size = len(content)
                info.mode = mode
                info.mtime = mtime
                bundle.addfile(info, io.BytesIO(content))
        return path

    def test_canonical_payload_ignores_tar_order_and_timestamps(self):
        entries = [('lib/main.dart', b'void main() {}', 0o644), ('tool/run', b'exit 0', 0o755)]
        first = inspect_archive(self.archive('first.tar.gz', entries), self.root / 'extracted')
        second = inspect_archive(self.archive('second.tar.gz', list(reversed(entries)), mtime=123))
        self.assertEqual(first['payloadSha256'], second['payloadSha256'])
        self.assertNotEqual(first['archiveSha256'], second['archiveSha256'])
        self.assertEqual(first['fileCount'], 2)
        verify_extracted(self.root / 'extracted', first)
        (self.root / 'extracted/lib/main.dart').write_text('changed')
        with self.assertRaisesRegex(ValueError, 'Candidate file changed'):
            verify_extracted(self.root / 'extracted', first)

    def test_payload_includes_executable_semantics(self):
        normal = inspect_archive(self.archive('normal.tar.gz', [('run', b'body', 0o644)]))
        executable = inspect_archive(self.archive('executable.tar.gz', [('run', b'body', 0o755)]))
        self.assertNotEqual(normal['payloadSha256'], executable['payloadSha256'])

    def test_unsafe_and_duplicate_entries_fail_before_extraction(self):
        for filename in ['../outside', '/absolute', r'..\outside']:
            with self.subTest(filename=filename):
                archive = self.archive('bad.tar.gz', [('safe', b'x', 0o644), (filename, b'y', 0o644)])
                target = self.root / 'not-created'
                with self.assertRaisesRegex(ValueError, 'Unsafe archive'):
                    inspect_archive(archive, target)
                self.assertFalse(target.exists())
        duplicate = self.archive('duplicate.tar.gz', [('safe', b'x', 0o644), ('./safe', b'y', 0o644)])
        with self.assertRaisesRegex(ValueError, 'Duplicate archive'):
            inspect_archive(duplicate)

    def test_links_are_rejected_and_existing_directory_preserved(self):
        archive = self.root / 'link.tar.gz'
        with tarfile.open(archive, 'w:gz') as bundle:
            info = tarfile.TarInfo('link')
            info.type = tarfile.SYMTYPE
            info.linkname = '../outside'
            bundle.addfile(info)
        with self.assertRaisesRegex(ValueError, 'Unsafe archive'):
            inspect_archive(archive)
        target = self.root / 'existing'
        target.mkdir()
        with self.assertRaisesRegex(ValueError, 'Refusing to replace'):
            inspect_archive(archive, target)
        self.assertTrue(target.is_dir())

    def test_extra_files_are_rejected_except_explicit_generated_cache(self):
        root = self.root / 'candidate'
        manifest = inspect_archive(self.archive('source.tar.gz', [('lib/main.dart', b'source', 0o644)]), root)
        cache = root / '.dart_tool'
        cache.mkdir()
        (cache / 'generated.json').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'Unexpected candidate file'):
            verify_extracted(root, manifest)
        verify_extracted(root, manifest, ('.dart_tool',))
        (root / 'lib/addition.dart').write_text('source')
        with self.assertRaisesRegex(ValueError, 'Unexpected candidate file'):
            verify_extracted(root, manifest, ('.dart_tool',))

    @unittest.skipIf(os.name == 'nt', 'POSIX file modes and symlink semantics')
    def test_changed_mode_and_symlinked_ancestor_are_rejected(self):
        root = self.root / 'candidate'
        manifest = inspect_archive(self.archive('source.tar.gz', [('lib/main.dart', b'source', 0o644)]), root)
        (root / 'lib/main.dart').chmod(0o755)
        with self.assertRaisesRegex(ValueError, 'executable mode changed'):
            verify_extracted(root, manifest)
        (root / 'lib/main.dart').chmod(0o644)
        (root / 'lib').rename(self.root / 'external')
        (root / 'lib').symlink_to(self.root / 'external', target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'Unexpected candidate file|Missing or replaced'):
            verify_extracted(root, manifest)


if __name__ == '__main__':
    unittest.main()
