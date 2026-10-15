# CI and verification tools

Use these tools to check SDK compatibility, package contents, and restart
behavior in consumer apps.

- [Verification guide](verification.md): platform, browser, documentation, and
  packaged skills checks, with commands and required results.
- [iOS stress guide](ios_stress.md): engine lifetime, WebView behavior, lifecycle
  transitions, and memory measurements.
- [CI workflow](../workflows/ci.yml): package, lint, build, compatibility, and
  desktop restart checks on every relevant push and pull request.
- [Platform proofs](../workflows/proofs.yml): browser restarts, the iOS simulator
  RunnerTests, and CocoaPods and SwiftPM builds. They run when the Dart API, web
  or Apple code, package manifest, or example change on `master`; run them
  manually before a release.
- [Documentation workflow](../workflows/docs-pages.yml): site validation and publication.

See [Contributing](../../CONTRIBUTING.md) for the development workflow.
