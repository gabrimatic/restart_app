# Restart verification

A restart check must observe the new Dart boot. A successful method-channel
response confirms that the request was accepted; startup can still fail later.
The tools in this directory run consumer apps and collect both sides of that
transition.

Run commands from the repository root unless a section says otherwise. For a
release, build consumers from the [candidate archive](#release-evidence).

## Local checks

Use the current stable Flutter SDK. Run the checks relevant to your change:

```sh
flutter pub get
flutter analyze
flutter test
flutter test --platform chrome test/restart_web_test.dart
python3 -m pip install -r .github/ci/requirements-readme-images.txt
python3 -B -m unittest discover -s .github/ci -p 'test_*.py'
```

Run `flutter pub get` and `flutter test` from `example/` for the example tests.
Native restart changes also need the platform checks below.

## SDK compatibility

Put the SDK you want to check on `PATH`, then run:

```sh
python3 .github/ci/check_compatibility.py --expected-flutter 3.22.0 --expected-dart 3.4
```

The script creates a consumer with a path dependency, runs the public API
regressions, analyzes the consumer, and builds its web app. The package's
repository development dependencies do not constrain that consumer. CI checks
the minimum, transitional, and current SDKs.

Apple builds separately check CocoaPods and Swift Package Manager in the
generated dependency graph. The legacy SwiftPM check uses Flutter 3.27, where
experimental integration is available on stable. Flutter 3.24 stable ignores
the SwiftPM feature option.

The plugin keeps its original SwiftPM manifest for older hosts. Current Flutter
may warn about the newer `FlutterFramework` dependency declaration. Adding it
unconditionally would break older generated graphs that do not provide that
package.

## Package skills

Use a current stable Flutter SDK and Python 3:

```sh
python3 .github/ci/check_skills.py
```

The script creates a temporary consumer, discovers the package skills, and
installs them twice with the Dart Skills CLI. It compares the installed files
with the package and analyzes every Dart code block as a standalone library.
For a release candidate, add `--package-dir /path/to/extracted-package`.
The publication dry run must include the skill files.

## Android

### Build and run

Build a disposable consumer with a current Flutter SDK, then run it on API 37:

```sh
python3 .github/ci/build_android_consumer.py /tmp/restart_android_current \
  --target-sdk 37 --compile-minor 0 --package-dir /path/to/extracted-package
python3 .github/ci/run_android_proof.py /tmp/restart_android_current/build/app/outputs/flutter-apk/app-debug.apk \
  --serial emulator-5554 --cycles 60
```

For API 21, use Flutter 3.22.0 and a fresh consumer directory. Build with
`--minimum --target-sdk 34` in place of `--target-sdk 37 --compile-minor 0`,
then run with `--cycles 30`. The minimum consumer updates the old app template
for the package's Java 17, AGP 8, and Kotlin 2 requirements. Current Flutter
requires newer Android versions even though the package supports API 21.

Use a dedicated emulator or test device. The runner installs and clears the
disposable `com.example.restart_android_proof` app.

### Required results

API 37 must complete 60 restarts and API 21 must complete 30. Requests repeat
in a three-mode sequence: platform default, explicit process, and force-kill.
Each mode must account for one third of the restarts.

Every cycle checks saved state, fresh Dart state, process behavior, two rejected
modes, and eight rejected concurrent native requests. The following launch must
read the preceding results from disk.

The controller pauses between restarts to exercise lifecycle transitions:

- Every five completed restarts, send the app Home and return. Require native
  and Dart lifecycle records, plus fresh UI dumps showing the app hidden and
  visible.
- After cycles 5, 15, 25, and so on, rotate to landscape and back. The disposable
  host permits Activity recreation on orientation changes. Require Activity
  destruction and recreation, a fresh Dart boot, and the same restart counter.
  Record these boots separately from plugin restarts.

The collector rejects stale run IDs, boot timestamps, and incomplete UI dumps.
It saves a JSON report and screenshot, stops the disposable app, and restores
the previous rotation settings, including settings that were absent.

The normal example also exercises preferences, SQLite, files, networking,
platform views, and other plugins before and after restart.

## Desktop

### Build and run

Create a Flutter desktop consumer, add a path dependency on the extracted
candidate, and copy `restart_proof_main.dart` into `lib/main.dart`. Before
building Linux, register the runner's original command-line arguments:

```sh
python3 .github/ci/prepare_linux_proof.py /path/to/consumer
```

Build the app, then pass its executable or macOS `.app` to the runner:

```sh
python3 .github/ci/run_desktop_proof.py /path/to/restart_proof.app --cycles 30
```

On Linux without a display, run the command through `xvfb-run -a`. CI builds
all three consumers from the shared candidate archive. It checks the extracted
manifest and resolved package origin before and after building, then uploads
those records with the runtime report.

### Required results and cleanup

The runner uses a unique run ID and clears only its named proof files. A run
must complete 30 native restarts and record 31 launches. Each cycle checks
alternating default/process modes, both rejected modes, concurrent-request
rejection, saved state, and fresh Dart state. The requested cycle count appears
in the saved state and final report.

Windows and Linux must preserve an argument containing spaces, quotes, and
Unicode. Linux also checks a preflight failure and an accepted request whose
`execv` fails with an invalid executable. The app must stay alive, the test
binary must be restored, and a retry must succeed. The runner restores its own
backup if the check is interrupted.

Each macOS or Windows restart must change PID. An older PID may be reused after
that process exits. Linux `execv` must retain the PID.

Before cleanup, only the final process may still run the disposable executable.
Cleanup stops recorded PIDs only after checking their executable identity. An
unrecorded matching process causes failure and is left alone. Raw boot records
remain available after validation failures. A passing report requires all
restart checks and confirmation that no owned process remains after cleanup.

### Windows failure recovery

The native harness injects launch, event, worker, wait, and resume failures. It
checks resource cleanup and verifies that a later request can recover:

```sh
cmake -S windows/tests -B /path/to/native-tests
cmake --build /path/to/native-tests --config Release
ctest --test-dir /path/to/native-tests -C Release --output-on-failure
```

### macOS launch failure

Create a separate consumer named `restart_macos_recovery` with a unique suffix
on its `com.example.restartMacosRecovery` bundle identifier. Build
`macos_recovery_main.dart` against the extracted candidate, then run:

```sh
python3 .github/ci/run_macos_recovery.py /path/to/restart_macos_recovery.app \
  --output /tmp/macos-recovery.json --build-provenance /path/to/build-provenance.json
```

The controller copies the app into a unique directory and waits for Dart and
native-channel readiness. It moves that copy's executable to a verified backup
before requesting a restart. The app must return `RESTART_FAILED`, keep its PID
and Dart state, and answer a native-channel ping.

After restoring identical executable bytes and permissions, the controller
requests another restart. This must produce a new PID and Dart boot, and the
old process must exit. Cleanup restores the executable after failures and stops
only recorded processes whose identity still matches. The report includes the
bundle, command sequence, failure, restoration, and cleanup records.

## iOS

### Engine lifecycle

Prepare a disposable consumer from the candidate archive. Run 100 engine
restarts on the current iOS Simulator runtime and 30 on the older runtime,
using a fresh consumer directory for each:

```sh
python3 .github/ci/prepare_ios_stress.py /tmp/candidate.tar.gz /tmp/ios-stress-current \
  --cycles 100 --sha256 <archive-sha256>
python3 .github/ci/run_ios_stress.py /tmp/ios-stress-current \
  --device <simulator-udid> --output /tmp/ios-stress-current.json
```

Requests alternate between default and explicit engine mode. Every new boot
must read saved state and complete a mounted WebView's JavaScript roundtrip.
XCUITest performs real Home/resume checkpoints every ten cycles; process mode
must be rejected at each checkpoint. The native PID must stay the same.

Each WebView scroll must stabilize within 2 seconds and remain at the expected
offset after the fixed settle interval. The host records weak object lifetimes,
completed `destroyContext` calls, resident memory, and physical footprint.
Growth above the larger of 30 MiB or 20%, continuing monotonic block growth, or
retained replacement objects requires investigation before a pass. The normal
plugin factory and root installer stay in use. See the
[iOS stress guide](ios_stress.md) for the measurement windows and full criteria.

### Native failure paths

Run `RunnerTests` on an iOS Simulator through the example's Xcode workspace.
The tests cover unsupported modes, concurrent engine and notification requests,
notification failure recovery, foreground scene selection, factory failure that
preserves the current engine, custom-window unavailability, and root-controller
protection after reconfiguration.

### Notification fallback

Test notification fallback separately from engine restart. Denied permission
must return a failure and leave the app running. Accepted fallback schedules a
notification and exits; the user must reopen the app through the notification.
It does not relaunch the process automatically.

Run both permission paths with the normal candidate example on an
English-language iOS Simulator:

```sh
python3 .github/ci/run_ios_fallback.py /tmp/candidate.tar.gz /tmp/fallback-denied \
  --sha256 <archive-sha256> --device <simulator-udid> --policy denied
python3 .github/ci/run_ios_fallback.py /tmp/candidate.tar.gz /tmp/fallback-allowed \
  --sha256 <archive-sha256> --device <simulator-udid> --policy allowed
```

Each command creates a unique bundle identifier and fresh permission state.
The runner verifies that the example's Dart and Swift lifecycle files are
unchanged before and after the build and run. XCUITest scrolls through the
example's checks, records boot and persistence markers, and answers the
notification prompt for that app.

Denial must preserve the process and Dart boot. A second denied request must
also recover, followed by a successful engine restart in the same process.
Acceptance must terminate the app. Tapping the delivered notification must
reopen it with a new PID and Dart boot.

Both paths require all example plugin checks, including the mounted WebView and
previous-boot file and SQLite markers. The runner saves build logs, the XCTest
result bundle, and validated JSON, then stops its disposable app. Use a fresh
consumer directory for each run.

## Web

### Build and run

Use Node 24 and the current Flutter SDK. From `example/`, build the browser
probe without service-worker registration:

```sh
flutter build web -t lib/web_restart_probe.dart --pwa-strategy=none
```

From `.github/ci/`, install and run the browser tests:

```sh
npm ci --ignore-scripts --no-audit --no-fund
npx playwright install chromium webkit
npm run test:web
```

On Linux, add `--with-deps` to the browser installation command. The runner
starts and stops its own local server. JavaScript builds run on Chromium and
WebKit at desktop and mobile viewport sizes. Each scenario runs three times
with a fresh context and run ID.

Rebuild the probe with `--wasm --pwa-strategy=none`, then run from `.github/ci/`:

```sh
RESTART_WEB_MODE=wasm npm run test:web
```

Wasm runs on Chromium and must receive `main.dart.wasm` without JavaScript
fallback.

### Required results

Both builds cover current, full, and relative URLs; changed, removed, and empty
fragments; identical URLs; non-root HTML base URLs; history; rejected modes;
invalid-URL recovery; opaque sandbox frames; and tab switches. Opaque frames
store their records in the parent because their own storage is unavailable.
The build omits service-worker registration, which browsers forbid in those
frames.

Every accepted restart must produce a fresh Dart boot and document time origin,
preserve saved state, reset in-memory state, and reach the exact destination
URL. History checks distinguish replacement navigation from the new entry
created by the hash shorthand.

### Background tabs

A headless browser may keep both tabs visible. Run the headed Chromium check to
require a hidden document before restart, a new document while still hidden,
and a visible page on return:

```sh
RESTART_WEB_HEADED=1 npx playwright test --config playwright.config.mjs \
  --workers 1 --repeat-each 1 --grep 'tab switch'
```

On Linux, set the environment variable first and run `npx` through
`xvfb-run -a`. The runner uses a temporary browser profile and connects with
`connectOverCDP` and `noDefaults: true` to avoid Playwright's focus emulation.
It records real visibility events.

These four checks cover default and full-fragment reloads at desktop and narrow
widths. Narrow desktop windows do not establish physical mobile-device behavior.
Repeat with `RESTART_WEB_MODE=wasm` for a Wasm build. On Linux, the disposable
browser uses Chromium's
[SwiftShader GL driver](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/gpu/swiftshader.md)
so WebGL is available without a GPU. The Wasm check still requires
`main.dart.wasm` and rejects JavaScript fallback.

### Reports and manual checks

Set these variables when you need non-default paths or ports:

| Variable | Value |
| --- | --- |
| `RESTART_WEB_BUILD` | Absolute build directory |
| `RESTART_WEB_PORT` | Unused local port |
| `RESTART_WEB_RESULTS` | Evidence directory |
| `RESTART_PACKAGE_SHA256` | Candidate archive hash to record |

Default reports go to `restart_app_web_results_js` or
`restart_app_web_results_wasm` in the system temporary directory. They include
browser versions, app responses, restart records, screenshots, and failure
traces. Verify the resolved package origin separately before building. CI builds
a copied example from the shared candidate archive and verifies its package
files again after execution.

For a manual check, serve a build from the repository root:

```sh
python3 .github/ci/serve_web_probe.py example/build/web
```

Visit `/deep/start?case=full-hash&run=<unique-id>#existing`. Omit `run` to see the
available scenarios. Use a new run ID for each attempt.

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

Use the [Pages workflow](../workflows/docs-pages.yml) commands to validate,
export, and prepare the site. The browser suite visits every page at desktop
and narrow widths in both themes. It checks resources, theme controls and stored
appearance, search and recovery from an index failure, keyboard dismissal and
restored focus, exact code copying, and mobile navigation. Screenshots of every
page support visual review.

The export supplies local controls and a generated search index because hosted
Mintlify interaction scripts do not run on GitHub Pages. README image checks
inspect SVG labels and raster content, so a broken badge fails even with an
HTTP 200 response. Changing package metrics are not treated as fixed values.
Also inspect the README on GitHub and in a pub.dev-style render.

Use a unique `RESTART_DOCS_RESULTS` directory for each run to preserve earlier
screenshots and failure traces.

## Release evidence

Create a candidate with the current Dart SDK after a clean publication dry run:

```sh
dart pub publish --dry-run
dart pub publish --to-archive=/tmp/restart_app-candidate.tar.gz
python3 .github/ci/package_archive.py /tmp/restart_app-candidate.tar.gz \
  --extract /tmp/restart_app-candidate --manifest /tmp/restart_app-candidate.json
```

The archive command does not upload the package. Record the archive SHA-256
and canonical payload manifest, then build release consumers from that
extracted directory. `check_skills.py`, `check_compatibility.py`, and
`build_android_consumer.py` accept `--package-dir /path/to/extracted-package`.
They reject Dart or native plugin metadata that points to another checkout.
For a manually prepared consumer, check the origin before and after building:

```sh
python3 .github/ci/candidate_package.py /path/to/consumer /path/to/extracted-package --platform web
```

Keep the verification harness outside the extracted package. Complete runtime
and skills checks before publication, then compare the final package selection
with the candidate manifest. Repeat affected checks if packaged files change.
After publication, verify that consumers receive the same files.

Record SDK and OS versions, build mode, app target SDK, packaging, and the
scenarios exercised. Simulator results do not establish physical-device or OEM
behavior. Desktop CI does not cover every distribution format, Linux
distribution, custom termination delegate, or host plugin lifecycle. Test the
app and distribution format you ship, including signed Store or MSIX builds
where applicable.
