#!/usr/bin/env python3
"""Inventory and safely extract the exact files selected by pub publish."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import tarfile


def inspect_archive(archive: Path, extract: Path | None = None) -> dict:
    files = []
    seen = set()
    if extract is not None:
        extract = extract.resolve()
        if extract.exists():
            raise ValueError(f'Refusing to replace existing extraction: {extract}')
    with tarfile.open(archive, 'r:*') as bundle:
        members = bundle.getmembers()
        for member in members:
            path = PurePosixPath(member.name)
            if (path.is_absolute() or '..' in path.parts or '\\' in member.name
                    or not path.parts or member.issym() or member.islnk()
                    or not (member.isfile() or member.isdir())):
                raise ValueError(f'Unsafe archive entry: {member.name}')
            normalized = path.as_posix()
            if normalized in seen:
                raise ValueError(f'Duplicate archive entry: {normalized}')
            seen.add(normalized)
            if member.isdir():
                continue
            stream = bundle.extractfile(member)
            if stream is None:
                raise ValueError(f'Unreadable archive entry: {normalized}')
            data = stream.read()
            files.append({
                'path': normalized,
                'sha256': hashlib.sha256(data).hexdigest(),
                'size': len(data),
                'executable': bool(member.mode & 0o111),
            })
        # Validate every entry before creating any extracted content.
        if extract is not None:
            extract.mkdir(parents=True)
            bundle.extractall(extract, members=members, filter='data')
    files.sort(key=lambda entry: entry['path'])
    canonical = json.dumps(files, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
    return {
        'archiveSha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
        'payloadSha256': hashlib.sha256(canonical).hexdigest(),
        'fileCount': len(files), 'files': files,
    }


def verify_extracted(root: Path, manifest: dict, exclusions: tuple[str, ...] = ()) -> None:
    root = root.resolve()
    allowed = []
    for exclusion in exclusions:
        relative = PurePosixPath(exclusion)
        if relative.is_absolute() or '..' in relative.parts or not relative.parts or '\\' in exclusion:
            raise ValueError(f'Invalid generated-cache exclusion: {exclusion}')
        allowed.append(relative.as_posix().rstrip('/'))
    expected = {entry['path'] for entry in manifest['files']}
    for path in root.rglob('*'):
        relative = path.relative_to(root).as_posix()
        if relative in expected:
            continue
        if any(relative == prefix or relative.startswith(prefix + '/') for prefix in allowed):
            continue
        if path.is_symlink() or path.is_file():
            raise ValueError(f'Unexpected candidate file: {relative}')
    for entry in manifest['files']:
        path = root / entry['path']
        if (path.is_symlink() or not path.is_file()
                or not path.resolve().is_relative_to(root)):
            raise ValueError(f'Missing or replaced candidate file: {entry["path"]}')
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError(f'Candidate file changed: {entry["path"]}')
        if os.name != 'nt' and bool(path.stat().st_mode & 0o111) != entry['executable']:
            raise ValueError(f'Candidate executable mode changed: {entry["path"]}')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--extract', type=Path)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--expected-manifest', type=Path)
    parser.add_argument('--verify-dir', type=Path)
    parser.add_argument('--allow-generated', action='append', default=[],
                        help='Record a relative generated-cache path excluded from extra-file checks.')
    args = parser.parse_args()
    report = inspect_archive(args.archive, args.extract)
    if args.expected_manifest:
        expected = json.loads(args.expected_manifest.read_text())
        if report['files'] != expected['files']:
            raise ValueError('Candidate payload differs from the expected manifest')
    if args.extract:
        verify_extracted(args.extract, report)
    if args.verify_dir:
        verify_extracted(args.verify_dir, report, tuple(args.allow_generated))
    report['verificationExclusions'] = args.allow_generated
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({key: value for key, value in report.items() if key != 'files'}))


if __name__ == '__main__':
    main()
