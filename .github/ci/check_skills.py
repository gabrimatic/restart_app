#!/usr/bin/env python3
"""Install bundled skills in a disposable Flutter consumer and analyze examples."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile


def run(*args, cwd):
    subprocess.run(args, cwd=cwd, check=True)


def files_under(root):
    return {
        path.relative_to(root): path.read_bytes()
        for path in root.rglob('*')
        if path.is_file()
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package-version', help='Verify a published version instead of a path dependency.')
    args = parser.parse_args()
    package = Path(__file__).resolve().parents[2]
    source = package / 'skills'
    expected = files_under(source)
    entries = sorted(source.glob('*/SKILL.md'))
    if not entries:
        raise RuntimeError('No package skills found')
    for entry in entries:
        name = entry.parent.name
        if not re.fullmatch(r'restart-app-[a-z0-9]+(?:-[a-z0-9]+)*', name):
            raise RuntimeError(f'Invalid package skill name: {name}')
        if not entry.read_text().startswith(f'---\nname: {name}\ndescription:'):
            raise RuntimeError(f'Missing or mismatched skill frontmatter: {entry}')

    with tempfile.TemporaryDirectory(prefix='restart_app_skills_') as temp:
        consumer = Path(temp)
        dependency = (
            json.dumps(args.package_version)
            if args.package_version
            else '\n    path: ' + json.dumps(str(package))
        )
        (consumer / 'pubspec.yaml').write_text(
            "name: restart_app_skills_consumer\npublish_to: none\n"
            "environment:\n  sdk: ^3.10.0\n"
            "dependencies:\n  flutter:\n    sdk: flutter\n"
            f"  restart_app: {dependency}\n"
        )
        run('flutter', 'pub', 'get', cwd=consumer)
        run('dart', 'run', 'skills@', 'get', 'restart_app', '--all', '--agent', 'generic', cwd=consumer)
        installed = consumer / '.agents' / 'skills'
        actual = files_under(installed)
        if actual != expected:
            missing = sorted(str(p) for p in expected.keys() - actual.keys())
            extra = sorted(str(p) for p in actual.keys() - expected.keys())
            changed = sorted(str(p) for p in expected.keys() & actual.keys() if expected[p] != actual[p])
            raise RuntimeError(f'Installed skills differ: missing={missing}, extra={extra}, changed={changed}')

        # A second run must preserve the installed contents.
        run('dart', 'run', 'skills@', 'get', 'restart_app', '--all', '--agent', 'generic', cwd=consumer)
        if files_under(installed) != expected:
            raise RuntimeError('Repeated installation changed skill contents')

        snippets = consumer / 'lib'
        snippets.mkdir()
        count = 0
        for path in sorted(installed.rglob('*.md')):
            for block in re.findall(r'^```dart\n(.*?)^```\s*$', path.read_text(), re.MULTILINE | re.DOTALL):
                count += 1
                (snippets / f'example_{count}.dart').write_text(block)
        if count == 0:
            raise RuntimeError('No Dart examples found')
        run('flutter', 'analyze', '--no-pub', cwd=consumer)
        print(f'Verified {len(entries)} skills, {len(expected)} installed files, and {count} Dart examples.')


if __name__ == '__main__':
    main()
