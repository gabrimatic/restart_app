import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Mintlify docs source is complete and old app docs are absent', () {
    expect(Directory('docs').existsSync(), isFalse);

    for (final path in [
      'doc/docs.json',
      'doc/index.mdx',
      'doc/quickstart.mdx',
      'doc/product/platform-behavior.mdx',
      'doc/product/ios-engine-restart.mdx',
      'doc/product/background-isolates.mdx',
      'doc/reference/api.mdx',
      'doc/reference/configuration.mdx',
      'doc/reference/linux.mdx',
      'doc/scripts/prepare-github-pages.mjs',
      '.github/workflows/docs-pages.yml',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: '$path should exist');
    }
  });

  test('README points readers at the published Pages docs', () {
    final readme = File('README.md').readAsStringSync();

    expect(readme, contains('https://gabrimatic.github.io/restart_app/'));
    expect(readme, isNot(contains('](doc/')));
    expect(readme, isNot(contains('](docs/')));
    expect(readme, isNot(contains('internal-docs')));
  });

  test('workflow triggers keep docs work in the docs workflow', () {
    final pagesWorkflow =
        File('.github/workflows/docs-pages.yml').readAsStringSync();
    final ciWorkflow = File('.github/workflows/ci.yml').readAsStringSync();

    expect(pagesWorkflow, contains('doc/**'));
    expect(pagesWorkflow, contains('README.md'));
    expect(pagesWorkflow, contains('mint validate'));
    expect(pagesWorkflow, contains('mint broken-links'));
    expect(pagesWorkflow, contains('mint export'));
    expect(pagesWorkflow, contains('actions/deploy-pages'));

    expect(ciWorkflow, contains('paths-ignore:'));
    expect(ciWorkflow, contains('doc/**'));
    expect(ciWorkflow, contains('.github/workflows/docs-pages.yml'));
    expect(ciWorkflow, contains('test/docs_site_test.dart'));
  });
}
