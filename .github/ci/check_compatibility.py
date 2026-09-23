#!/usr/bin/env python3
"""Exercise restart_app as a real dependency from a disposable Flutter app."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import shutil

from candidate_package import assert_package_origin, package_directory


def run(*args: str, cwd: Path) -> None:
    subprocess.run(args, cwd=cwd, check=True)


def flutter_version() -> tuple[str, str]:
    result = subprocess.run(
        ("flutter", "--version", "--machine"),
        check=True,
        capture_output=True,
        text=True,
    )
    details = json.loads(result.stdout)
    return details["frameworkVersion"], details["dartSdkVersion"]


def has_version_prefix(actual: str, expected: str) -> bool:
    return actual == expected or actual.startswith(f"{expected}.")


def write_consumer(consumer: Path, package: Path) -> None:
    run("flutter", "create", "--platforms=web", "--project-name",
        "restart_app_compat_consumer", str(consumer), cwd=consumer)
    shutil.rmtree(consumer / "test", ignore_errors=True)
    (consumer / "analysis_options.yaml").write_text("analyzer:\n  errors:\n    unused_import: error\n")
    (consumer / "test").mkdir()
    (consumer / "pubspec.yaml").write_text(
        """name: restart_app_compat_consumer
publish_to: none

environment:
  sdk: ">=3.4.0 <4.0.0"
  flutter: ">=3.22.0"

dependencies:
  flutter:
    sdk: flutter
  restart_app:
    path: {package}

dev_dependencies:
  flutter_test:
    sdk: flutter
""".format(package=json.dumps(str(package)))
    )
    (consumer / "lib/main.dart").write_text(
        """import 'package:flutter/widgets.dart';
import 'package:restart_app/restart_app.dart';

void main() {
  runApp(const _ConsumerApp());
}

class _ConsumerApp extends StatelessWidget {
  const _ConsumerApp();

  @override
  Widget build(BuildContext context) {
    final mode = RestartMode.platformDefault.name;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text('restart_app consumer: $mode'),
    );
  }
}
"""
    )
    # Run the actual public API regression suite with the consumer's SDK and
    # dependency resolution. The package's development tools are not imposed
    # on applications depending on it.
    shutil.copyfile(package / "test/restart_app_test.dart",
                    consumer / "test/restart_app_test.dart")



def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-flutter", required=True)
    parser.add_argument("--expected-dart", required=True)
    parser.add_argument("--label", default="consumer")
    parser.add_argument('--package-dir', type=package_directory,
                        help='Use an extracted package candidate instead of the checkout.')
    args = parser.parse_args()

    package = args.package_dir or package_directory(Path(__file__).resolve().parents[2])
    actual_flutter, actual_dart = flutter_version()
    if actual_flutter != args.expected_flutter:
        raise RuntimeError(
            f"{args.label}: expected Flutter {args.expected_flutter}, "
            f"got {actual_flutter}"
        )
    if not has_version_prefix(actual_dart, args.expected_dart):
        raise RuntimeError(
            f"{args.label}: expected Dart {args.expected_dart}.x, got {actual_dart}"
        )

    with tempfile.TemporaryDirectory(prefix="restart_app_compat_") as temp:
        consumer = Path(temp)
        write_consumer(consumer, package)
        run("flutter", "pub", "get", cwd=consumer)
        assert_package_origin(consumer, package, required_platforms=('web',))
        run("flutter", "analyze", cwd=consumer)
        run("flutter", "test", cwd=consumer)
        run("flutter", "build", "web", cwd=consumer)
        assert_package_origin(consumer, package, required_platforms=('web',))

    print(
        f"Verified {args.label} consumer with Flutter {actual_flutter} "
        f"and Dart {actual_dart}."
    )


if __name__ == "__main__":
    main()
