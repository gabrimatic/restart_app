"""Check that disposable consumers use the intended restart_app package files."""

from __future__ import annotations

import json
import argparse
from pathlib import Path
import re
from urllib.parse import urljoin, urlsplit
from urllib.request import url2pathname


def _has_scalar(pubspec: str, key: str, value: str) -> bool:
    return re.search(
        rf"^{re.escape(key)}:[ \t]*(['\"]?){re.escape(value)}\1[ \t]*(?:#.*)?$",
        pubspec,
        re.MULTILINE,
    ) is not None


def package_directory(value: str | Path) -> Path:
    """Validate package identity before generating a consumer or starting a build."""
    directory = Path(value).expanduser().resolve()
    pubspec = directory / 'pubspec.yaml'
    if not pubspec.is_file():
        raise ValueError(f'Package directory has no pubspec.yaml: {directory}')
    if not _has_scalar(pubspec.read_text(), 'name', 'restart_app'):
        raise ValueError(f'Package directory is not restart_app: {directory}')
    return directory


def resolved_package_directory(consumer: Path) -> Path:
    config_path = consumer.resolve() / '.dart_tool/package_config.json'
    config = json.loads(config_path.read_text())
    packages = [entry for entry in config['packages']
                if entry.get('name') == 'restart_app']
    if len(packages) != 1:
        raise RuntimeError('Expected exactly one resolved restart_app package')
    root_uri = urlsplit(urljoin(config_path.as_uri(), packages[0]['rootUri']))
    if (root_uri.scheme != 'file' or root_uri.netloc not in ('', 'localhost')
            or root_uri.query or root_uri.fragment):
        raise RuntimeError(f'Unexpected restart_app package URI: {root_uri.geturl()}')
    return package_directory(Path(url2pathname(root_uri.path)))


def assert_package_origin(
    consumer: Path,
    expected: Path,
    *,
    required_platforms: tuple[str, ...] = (),
    require_native_metadata: bool = True,
) -> None:
    """Reject stale Dart or native metadata pointing back to another checkout."""
    if required_platforms and not require_native_metadata:
        raise ValueError('Required native platforms cannot omit native metadata')
    expected = package_directory(expected)
    actual = resolved_package_directory(consumer)
    if actual != expected:
        raise RuntimeError(f'restart_app resolved to {actual}; expected {expected}')

    metadata_path = consumer / '.flutter-plugins-dependencies'
    if not metadata_path.is_file():
        if not require_native_metadata:
            print(f'Verified restart_app Dart origin: {expected} (Dart-only fixture)')
            return
        raise RuntimeError(f'Missing Flutter plugin metadata: {metadata_path}')
    metadata = json.loads(metadata_path.read_text())
    found = set()
    for platform, entries in metadata.get('plugins', {}).items():
        matches = [entry for entry in entries if entry.get('name') == 'restart_app']
        if len(matches) > 1:
            raise RuntimeError(f'Duplicate restart_app plugin metadata for {platform}')
        for entry in matches:
            native_root = Path(entry['path'])
            if not native_root.is_absolute():
                native_root = consumer / native_root
            native_root = native_root.resolve()
            if native_root != expected:
                raise RuntimeError(
                    f'{platform} restart_app plugin uses {native_root}; expected {expected}'
                )
            found.add(platform)
    if not found:
        raise RuntimeError('Flutter plugin metadata contains no restart_app plugin')
    missing = set(required_platforms) - found
    if missing:
        raise RuntimeError(f'Missing restart_app plugin platforms: {sorted(missing)}')
    print(f'Verified restart_app origin: {expected} ({", ".join(sorted(found))})')


def assert_package_version(package: Path, version: str) -> None:
    if not _has_scalar((package / 'pubspec.yaml').read_text(), 'version', version):
        raise RuntimeError(f'Resolved restart_app does not have requested version {version}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('consumer', type=Path)
    parser.add_argument('package', type=package_directory)
    parser.add_argument('--platform', action='append', default=[])
    arguments = parser.parse_args()
    assert_package_origin(arguments.consumer, arguments.package,
                          required_platforms=tuple(arguments.platform))
