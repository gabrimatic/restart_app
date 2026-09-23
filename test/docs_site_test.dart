import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('Mintlify docs source is complete and old app docs are absent', () {
    expect(Directory('docs').existsSync(), isFalse);

    for (final path in [
      'doc/docs.json',
      'doc/index.mdx',
      'doc/quickstart.mdx',
      'doc/agent-skills.mdx',
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

  test('iOS docs explain UIScene integration', () {
    final docs = {
      'doc/product/ios-engine-restart.mdx':
          File('doc/product/ios-engine-restart.mdx').readAsStringSync(),
    };

    for (final entry in docs.entries) {
      expect(
        entry.value,
        contains('FlutterImplicitEngineDelegate'),
        reason: '${entry.key} should cover Flutter UIScene apps',
      );
      expect(
        entry.value,
        contains('didInitializeImplicitFlutterEngine'),
        reason: '${entry.key} should show implicit engine registration',
      );
      expect(
        entry.value,
        contains('UIWindowScene'),
        reason: '${entry.key} should explain scene window selection',
      );
      expect(
        entry.value,
        contains('windowProvider'),
        reason: '${entry.key} should cover custom scene/window shells',
      );
    }
  });

  final ci = _workflow('ci');
  final pages = _workflow('docs-pages');
  for (final event in ['push', 'pull_request']) {
    test('$event routes every release surface to CI', () {
      for (final path in [
        '.github/workflows/ci.yml',
        '.github/ci/run_desktop_proof.py',
        '.pubignore',
        'analysis_options.yaml',
        'pubspec.yaml',
        'pubspec.lock',
        'skills/restart-app-integration/SKILL.md',
        'lib/restart_app.dart',
        'android/src/main/kotlin/gabrimatic/info/restart/RestartPlugin.kt',
        'ios/restart_app/Sources/restart_app/RestartAppPlugin.swift',
        'linux/restart_app_plugin.cc',
        'macos/restart_app/Sources/restart_app/RestartAppPlugin.swift',
        'windows/restart_app_relaunch.cpp',
        'example/lib/main.dart',
        'test/restart_app_test.dart',
        'test_apps/ios_deep_matrix/lib/main.dart',
      ]) {
        expect(_triggered(ci, event, 'master', [path]), isTrue,
            reason: '$event must validate $path');
        expect(_triggered(pages, event, 'master', [path]), isFalse,
            reason: '$path alone does not change the Pages site');
      }
    });

    test('$event keeps docs-only work in the docs workflow', () {
      for (final path in [
        'doc/quickstart.mdx',
        'doc/scripts/prepare-github-pages.mjs',
        'README.md',
        '.github/workflows/docs-pages.yml',
        'test/docs_site_test.dart',
      ]) {
        expect(_triggered(ci, event, 'master', [path]), isFalse,
            reason: '$event should not run plugin CI for $path alone');
        expect(_triggered(pages, event, 'master', [path]), isTrue,
            reason: '$event must validate $path');
      }
      expect(
        _triggered(ci, event, 'master',
            ['test/docs_site_test.dart', 'lib/restart_app.dart']),
        isTrue,
        reason: 'A docs test change cannot suppress a plugin change',
      );
    });

    test('$event validates changes to the image gate in both workflows', () {
      for (final path in [
        '.github/ci/check_readme_images.py',
        '.github/ci/test_readme_images.py',
        '.github/ci/requirements-readme-images.txt',
      ]) {
        expect(_triggered(ci, event, 'master', [path]), isTrue);
        expect(_triggered(pages, event, 'master', [path]), isTrue);
      }
    });
  }

  test('candidate dispatch builds docs but only master can deploy', () {
    final jobs = pages['jobs'] as YamlMap;
    for (final scenario in [
      ('workflow_dispatch', 'refs/heads/stabilize-1.10.0', false),
      ('workflow_dispatch', 'refs/heads/master', true),
      ('push', 'refs/heads/master', true),
      ('pull_request', 'refs/pull/123/merge', false),
    ]) {
      final (event, ref, shouldDeploy) = scenario;
      if (event == 'workflow_dispatch') {
        expect(_triggered(pages, event, ref, []), isTrue);
      }
      expect(_jobEnabled(jobs['build'] as YamlMap, event, ref), isTrue);
      expect(_jobEnabled(jobs['deploy'] as YamlMap, event, ref), shouldDeploy,
          reason: '$event at $ref must respect the publication boundary');
    }
    expect((jobs['deploy'] as YamlMap)['needs'], 'build');
  });
}

YamlMap _workflow(String name) =>
    loadYaml(File('.github/workflows/$name.yml').readAsStringSync()) as YamlMap;

bool _triggered(
    YamlMap workflow, String event, String branch, List<String> changedPaths) {
  final events = workflow['on'] as YamlMap;
  if (!events.containsKey(event)) return false;
  if (event == 'workflow_dispatch') return true;
  final filters = events[event] as YamlMap;
  final branches = (filters['branches'] as YamlList).cast<String>();
  final paths = (filters['paths'] as YamlList).cast<String>();
  return _matchesPatterns(branch, branches) &&
      changedPaths.any((path) => _matchesPatterns(path, paths));
}

// GitHub applies paths in order, so a later negative pattern can exclude a
// match. These workflows use literal paths, *, ** and ?. Fail on other syntax
// instead of treating an unsupported GitHub glob as meaningful coverage.
bool _matchesPatterns(String value, Iterable<String> patterns) {
  var matches = false;
  for (final pattern in patterns) {
    final negative = pattern.startsWith('!');
    final glob = negative ? pattern.substring(1) : pattern;
    if (RegExp(r'[\[\]{}+!]').hasMatch(glob)) {
      throw FormatException('Unsupported workflow path pattern: $pattern');
    }
    final expression = StringBuffer('^');
    for (var i = 0; i < glob.length; i++) {
      if (glob[i] == '*' && i + 1 < glob.length && glob[i + 1] == '*') {
        expression.write('.*');
        i++;
      } else if (glob[i] == '*') {
        expression.write('[^/]*');
      } else if (glob[i] == '?') {
        expression.write('[^/]');
      } else {
        expression.write(RegExp.escape(glob[i]));
      }
    }
    expression.write(r'$');
    if (RegExp(expression.toString()).hasMatch(value)) matches = !negative;
  }
  return matches;
}

bool _jobEnabled(YamlMap job, String event, String ref) {
  final condition = job['if'];
  if (condition == null) return true;
  // Evaluate the actual parsed condition against contexts, rather than only
  // asserting that a branch name appears somewhere in the workflow source.
  return (condition as String).split('&&').every((clause) {
    final match =
        RegExp(r"^\s*github\.(event_name|ref)\s*(==|!=)\s*'([^']*)'\s*$")
            .firstMatch(clause);
    if (match == null) {
      throw FormatException('Unsupported job condition: $condition');
    }
    final actual = match[1] == 'event_name' ? event : ref;
    return match[2] == '==' ? actual == match[3] : actual != match[3];
  });
}
