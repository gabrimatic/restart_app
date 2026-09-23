# Restart verification

A successful method-channel result means that a restart was accepted. It does
not prove that a replacement engine or application completed startup. These
checks run consumer applications and require evidence from the new launch.

## SDK compatibility

With the desired Flutter SDK on `PATH`, run:

```sh
python3 .github/ci/check_compatibility.py --expected-flutter 3.22.0 --expected-dart 3.4
```

This resolves the package as a path dependency, runs the public API regression
suite using that SDK, analyzes the consumer, and builds its web application.
The package's development-tool constraints do not apply to the consumer.
CI repeats this on the minimum, transitional, and current SDKs.

Apple builds separately verify CocoaPods and SwiftPM participation in the
generated dependency graph. The legacy SwiftPM check uses Flutter 3.27, where
the experimental integration is available on stable. Flutter 3.24 stable
ignores the SwiftPM feature option. The plugin retains its original SwiftPM
manifest to support both generations. Current Flutter may warn about the
newer `FlutterFramework` dependency declaration; adding it unconditionally
would break older hosts whose generated graph does not provide that package.

## Android

Build a fresh probe with a current Flutter SDK:

```sh
python3 .github/ci/build_android_consumer.py /tmp/restart_android_current \
  --target-sdk 37 --compile-minor 0 --package-dir /path/to/extracted-package
python3 .github/ci/run_android_proof.py /tmp/restart_android_current/build/app/outputs/flutter-apk/app-debug.apk \
  --serial emulator-5554 --cycles 60
```

For Android 21, put Flutter 3.22.0 on `PATH` and build with
`--minimum --target-sdk 34` instead, then run with `--cycles 30`. The minimum consumer updates the old app
template to the package's Java 17, AGP 8, and Kotlin 2 requirements. Current
Flutter itself requires newer Android versions even though the plugin keeps
its Android 21 minimum.

The runner installs and clears only the disposable
`com.example.restart_android_proof` app. It requires 60 successful restarts on
API 37 and 30 on API 21, repeating default, explicit process, and force-kill
requests in equal counts. Each launch checks persisted state, fresh Dart state,
process behavior, two rejected modes, and eight rejected concurrent native
requests. The next launch requires the preceding results to have persisted.

The external controller pauses between restarts. Every five completed restarts,
it sends the app Home and returns, requiring native and Dart lifecycle records
plus fresh UI dumps that show the app hidden and visible. After cycles 5, 15,
25, and so on, it rotates to landscape and back. The disposable host permits
Activity recreation on orientation changes; the report requires Activity
destruction and recreation, a fresh Dart boot, and an unchanged restart counter.
Rotation boots are counted separately from plugin restarts.

The collector rejects stale run IDs, boot timestamps, and incomplete UI dumps.
It saves a JSON report and screenshot, stops the disposable app, and restores
the exact previous rotation settings, including absent values, in cleanup.
Use a dedicated emulator or test device.
The example app separately exercises shared preferences, SQLite, file storage,
networking, platform views, and other plugins before and after restart.

## Desktop

Create a Flutter desktop consumer, add a path dependency on the extracted candidate, and
copy `restart_proof_main.dart` into its `lib/main.dart`. Before building Linux,
wire the generated runner's original command-line arguments:

```sh
python3 .github/ci/prepare_linux_proof.py /path/to/consumer
```

Build the application, then pass its executable or macOS `.app` to the runner:

```sh
python3 .github/ci/run_desktop_proof.py /path/to/restart_proof.app --cycles 30
```

On Linux, run the command under `xvfb-run -a` if no display is available. CI
builds all three consumers from the shared candidate archive, verifies the
extracted file manifest and package origin around each build, and uploads that
evidence with the runtime report. The runner clears only its named
proof files, supplies a unique run ID, and requires 30 native restarts and 31
launches. It checks alternating default/process modes, both rejected modes,
concurrent-request rejection on every cycle, saved state, and fresh Dart state.
The requested count is explicit in the persisted state and final report.
Windows and Linux must preserve an argument containing
spaces, quotes, and Unicode. Linux also checks preflight failure and an accepted
restart whose `execv` fails with an invalid executable, then restores the test
binary and requires a successful retry. The runner restores its own backup if
the test is interrupted. macOS and Windows must change PID; Linux `execv`
retains PID. Before cleanup, only the final process may still run the disposable
executable. Cleanup stops only PIDs recorded by the current run after checking
executable identity; unrecorded matching processes cause failure and are left
alone. The report is written after confirming no owned process remains.

The separate Windows native harness injects launch, event, worker, wait, and
resume failures, checks resource cleanup, and confirms later requests recover:

```sh
cmake -S windows/tests -B /path/to/native-tests
cmake --build /path/to/native-tests --config Release
ctest --test-dir /path/to/native-tests -C Release --output-on-failure
```

For the supplemental macOS launch-error check, create a separate consumer named
`restart_macos_recovery`, use a unique `com.example.restartMacosRecovery` bundle
identifier suffix, and build `macos_recovery_main.dart` against the extracted
candidate. Pass the built app to the external controller:

```sh
python3 .github/ci/run_macos_recovery.py /path/to/restart_macos_recovery.app \
  --output /tmp/macos-recovery.json --build-provenance /path/to/build-provenance.json
```

The controller copies the app to a unique run directory and waits for Dart and
native-channel readiness. It moves only that copy's executable to a verified
backup, then commands a restart. The app must return `RESTART_FAILED`, retain its
PID and Dart memory, and answer a native-channel ping. The controller restores
identical bytes and permissions before commanding a successful retry, which
must create a fresh PID and Dart boot and allow the old process to exit. Its
cleanup also restores the executable after failures and stops only recorded
processes after checking their executable identity. Each JSON report preserves
the run, bundle, command sequence, failure, restoration, and cleanup evidence.

## iOS

Use a candidate archive to prepare a disposable consumer. Run 100 engine
restarts on the current iOS Simulator runtime and 30 on the older runtime,
with a fresh consumer directory for each:

```sh
python3 .github/ci/prepare_ios_stress.py /tmp/candidate.tar.gz /tmp/ios-stress-current \
  --cycles 100 --sha256 <archive-sha256>
python3 .github/ci/run_ios_stress.py /tmp/ios-stress-current \
  --device <simulator-udid> --output /tmp/ios-stress-current.json
```

The gate alternates default and explicit engine mode, verifies persisted state
and a mounted WebView's JavaScript roundtrip on every new boot, and uses
XCUITest for real Home/resume checkpoints every ten cycles. Process mode must
be rejected at each checkpoint. The native PID must remain unchanged.
Each WebView scroll must stabilize within 2 seconds and remain at the expected
offset after the fixed settle interval; both measurements are required.

The QA host records weak engine/controller/WebView lifetimes and forwards
`destroyContext` calls to verify completion. The normal plugin factory and
root installer remain unchanged. It records resident memory and physical
footprint after a fixed settle interval. Growth above the larger of 30 MiB or
20%, continuing monotonic block growth, or retained replacement objects
requires investigation before the gate passes. See the [iOS stress guide](ios_stress.md)
for comparison windows, instrumentation boundaries, and report details.

Run `RunnerTests` on an iOS simulator through the example's Xcode workspace.
These tests cover unsupported modes, concurrent engine and notification
requests, notification failure recovery, foreground scene selection, factory
failure without destroying the current engine, custom-window unavailability,
and restoring root-controller protection after reconfiguration.

Test notification fallback separately. Denied permission must report failure
without exiting. Accepted fallback exits and requires the user to reopen the
app through its notification. It is not an automatic process relaunch.

Run the normal candidate example through both real notification-permission paths
on an English-language iOS Simulator:

```sh
python3 .github/ci/run_ios_fallback.py /tmp/candidate.tar.gz /tmp/fallback-denied \
  --sha256 <archive-sha256> --device <simulator-udid> --policy denied
python3 .github/ci/run_ios_fallback.py /tmp/candidate.tar.gz /tmp/fallback-allowed \
  --sha256 <archive-sha256> --device <simulator-udid> --policy allowed
```

Each command creates a unique disposable bundle identifier with fresh permission
state. The example's Dart files and Swift lifecycle sources remain unchanged and
are verified before and after building and running. XCUITest scrolls through the
actual example checks, records their boot and persistence markers, and handles
the notification prompt for that specific app. Denial must leave the same app
process and Dart boot alive; a second denied request must also recover, followed
by a successful same-process engine restart. Acceptance must terminate the app;
tapping the delivered notification must reopen it with a different PID and boot.
Both paths require all example plugin checks, including the mounted WebView and
previous-boot file and SQLite markers. The runner preserves build logs, the
XCTest result bundle, and validated JSON evidence, and stops only its disposable
app. Use a fresh consumer directory for each run.

## Web

Use Node 24 and the current Flutter SDK. From `example/`, build the browser
probe without service-worker registration:

```sh
flutter build web -t lib/web_restart_probe.dart --pwa-strategy=none
```

From `.github/ci/`, install and run the isolated browser tests:

```sh
npm ci --ignore-scripts --no-audit --no-fund
npx playwright install chromium webkit
npm run test:web
```

On Linux, add `--with-deps` to the browser installation command. The runner
starts and stops its own local server. JavaScript runs on Chromium and WebKit
at desktop and mobile viewport sizes. Each scenario runs three times with a
new context and run ID.

Rebuild the probe with `--wasm --pwa-strategy=none`, then run from `.github/ci/`:

```sh
RESTART_WEB_MODE=wasm npm run test:web
```

The Wasm suite uses Chromium and requires an actual `main.dart.wasm` response
without JavaScript fallback. Both suites cover the current route, full and
relative destinations, changed/removed/empty fragments, identical URLs,
non-root HTML base URLs, history, rejected modes, invalid-URL recovery,
opaque sandbox frames, and a tab switch. Opaque frames retain proof state in
their parent because their own storage is unavailable. The QA build omits
service-worker registration, which browsers forbid in those frames.

Every accepted restart requires a fresh Dart boot and document time origin,
saved state, reset memory state, and the exact destination URL. History checks
distinguish replacement navigation from the hash shorthand's added entry.
The tab-switch record includes observed visibility; a headless browser may keep
both tabs visible. Run the separate headed Chromium check to require a hidden
document before restarting, a new document while still hidden, and a visible
page on return:

```sh
RESTART_WEB_HEADED=1 npx playwright test --config playwright.config.mjs \
  --workers 1 --repeat-each 1 --grep 'tab switch'
```

On Linux, set the environment variable first and run the `npx` command through
`xvfb-run -a`. The runner owns a temporary browser profile and disables
Playwright's default focus emulation through
`connectOverCDP` with `noDefaults: true`. It does not synthesize visibility
events. These four checks cover default and full-fragment reloads at desktop
and narrow widths; narrow headed windows are viewport checks, not physical
mobile-device evidence. Repeat with `RESTART_WEB_MODE=wasm` for a Wasm build.

Set `RESTART_WEB_BUILD` to an absolute build directory, `RESTART_WEB_PORT` to
an unused port, and `RESTART_WEB_RESULTS` to an evidence directory when needed.
The default results directory is `restart_app_web_results_js` or
`restart_app_web_results_wasm` in the system temporary directory. Reports include
browser versions, application responses, restart fields, screenshots, and
failure traces. `RESTART_PACKAGE_SHA256` records a candidate archive hash in
the report; verify the consumer's package origin separately before building.
The CI browser jobs build a copied example against the shared publication
archive and verify that its package files remain unchanged after execution.

For manual checks, serve a build from the repository root:

```sh
python3 .github/ci/serve_web_probe.py example/build/web
```

Visit `/deep/start?case=full-hash&run=<unique-id>#existing`. The page lists the
available scenarios when the `run` parameter is absent. Use a new run ID for
each attempt.

## Documentation

```sh
node --test doc/scripts/prepare-github-pages.test.mjs
python3 -m pip install -r .github/ci/requirements-readme-images.txt
python3 .github/ci/check_readme_images.py
npm ci --prefix .github/ci
npx --prefix .github/ci playwright install chromium
RESTART_DOCS_SITE=/path/to/prepared/export \
  npx --prefix .github/ci playwright test --config .github/ci/docs_playwright.config.mjs
```

Validate, export, and prepare the docs using the Pages workflow commands. The
browser suite visits every documentation page at desktop and narrow widths in
both themes. It checks resource failures, visible theme icons, stored appearance,
search and retry after an index failure, keyboard dismissal and restored focus,
exact code copying, and mobile navigation. It captures every rendered page for
visual review. The export uses local controls and a generated search index
because hosted Mintlify interaction scripts do not run on GitHub Pages.

README image validation examines SVG labels and raster content, so an HTTP200
error badge fails. It does not treat changing package metrics as fixed values.
Inspect the candidate README on GitHub and in a pub.dev-style render as well.
Use a unique `RESTART_DOCS_RESULTS` directory for each evidence run so earlier
failure traces and screenshots remain available.

## Release evidence

Create the candidate with the current Dart SDK's package selection after a
clean publish dry run:

```sh
dart pub publish --dry-run
dart pub publish --to-archive=/tmp/restart_app-candidate.tar.gz
```

The second command writes an archive without uploading it. Record its SHA256,
extract it into a separate directory, and use that directory for release
consumers. `check_skills.py`, `check_compatibility.py`, and
`build_android_consumer.py` accept `--package-dir /path/to/extracted-package`.
They reject Dart or native plugin metadata pointing to another checkout.
Check a manually prepared consumer before and after building:

```sh
python3 .github/ci/candidate_package.py /path/to/consumer /path/to/extracted-package --platform web
```

Keep the QA harness outside the extracted package. Finish the runtime and
skills checks before publication, then compare the final publication selection
with the frozen candidate. Changes to packaged files require repeating the
affected checks. Postpublication verification confirms delivery of the same
files.

Record the SDK, OS, build mode, app target SDK, packaging, and actual scenarios.
A simulator run does not establish physical-device or OEM behavior. A desktop
CI application does not establish signed Store/MSIX behavior, every Linux
distribution, custom termination delegates, or every host application's plugin
lifecycle. Test the application and distribution format you ship.
