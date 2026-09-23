# Contributing

Keep changes focused and include enough detail to reproduce the problem or try
the new behavior.

## Get started

Use a current stable Flutter SDK for repository development:

```sh
git clone https://github.com/gabrimatic/restart_app.git
cd restart_app
flutter pub get
cd example
flutter pub get
flutter run -d <device>
```

The example has higher SDK requirements than the package. Use the
[compatibility checks](.github/ci/verification.md#sdk-compatibility) to test the
package with older supported SDKs.

## Find the implementation

The shared API and platform implementations use the `restart` method channel.

| Component | Source |
| --- | --- |
| Public Dart API | [lib/restart_app.dart](lib/restart_app.dart) |
| Web | [lib/restart_web.dart](lib/restart_web.dart) |
| Android | [RestartPlugin.kt](android/src/main/kotlin/gabrimatic/info/restart/RestartPlugin.kt) |
| iOS | [RestartAppPlugin.swift](ios/restart_app/Sources/restart_app/RestartAppPlugin.swift) |
| Linux | [restart_app_plugin.cc](linux/restart_app_plugin.cc) |
| macOS | [RestartAppPlugin.swift](macos/restart_app/Sources/restart_app/RestartAppPlugin.swift) |
| Windows | [restart_app_plugin.cpp](windows/restart_app_plugin.cpp) |

Read the [platform behavior guide](doc/product/platform-behavior.mdx) before
changing a restart path. In particular, iOS engine restart depends on host
configuration and keeps the native process alive. Notification fallback is an
explicit opt-in that requires the user to reopen the app.

## Prepare a pull request

- Keep one feature or fix per pull request and avoid unrelated formatting.
- Run `flutter analyze` and the tests relevant to the change.
- Run the affected platform when changing native restart behavior. Record the
  device or simulator, OS, build mode, and result.
- Update the documentation and `CHANGELOG.md` for user-facing changes.
- Leave version changes to the release process.

The [verification guide](.github/ci/verification.md) has the commands for unit
tests, compatibility checks, native restarts, browser behavior, and documentation.
A restart check must observe the new Dart boot as well as the accepted request.

## Maintain package skills

Consumer instructions live in `skills/`, with one `SKILL.md` in each
`restart-app-*` directory. Match the frontmatter name to its directory, keep
referenced material inside the skill, and make Dart examples complete enough to
analyze on their own. Update the relevant skill when an API or platform contract
changes.

Run the [packaged skills check](.github/ci/verification.md#package-skills) to
verify discovery, repeated installation, file contents, and Dart examples.

## Report a problem

Use the [bug report template](https://github.com/gabrimatic/restart_app/issues/new?template=bug_report.md)
and include the package and Flutter versions, platform, restart options, and a
small reproduction. For a feature request, explain the use case and expected
behavior.

Report vulnerabilities privately through the process in
[SECURITY.md](SECURITY.md).
