#!/usr/bin/env python3
"""Preserve the disposable Linux consumer's original argv across execv."""
from __future__ import annotations

import argparse
from pathlib import Path
import re


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('consumer', type=Path)
    args = parser.parse_args()
    linux = args.consumer.resolve() / 'linux'
    candidates = [linux / 'runner/main.cc', linux / 'main.cc']
    source = next((path for path in candidates if path.is_file()), None)
    if source is None:
        raise RuntimeError('Could not find the generated Linux main.cc.')
    contents = source.read_text()
    call = 'restart_app_plugin_store_argv(argc, argv);'
    if call not in contents:
        contents, count = re.subn(
            r'(int\s+main\s*\(\s*int\s+argc\s*,\s*char\s*\*\*\s*argv\s*\)\s*\{)',
            r'\1\n  ' + call, contents, count=1)
        if count != 1:
            raise RuntimeError('Could not identify the generated Linux main function.')
        contents = '#include <restart_app/restart_app_plugin.h>\n' + contents
        source.write_text(contents)
    cmake = linux / 'CMakeLists.txt'
    contents = cmake.read_text()
    link = 'target_link_libraries(${BINARY_NAME} PRIVATE restart_app_plugin)'
    if link not in contents:
        cmake.write_text(contents + '\n' + link + '\n')
    print(f'Prepared original argv preservation in {source}')


if __name__ == '__main__':
    main()
