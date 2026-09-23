# iOS lifecycle stress

Run repeated engine restarts in a disposable consumer built from a candidate
package archive. This checks Dart startup, host lifecycle, WebView behavior,
object cleanup, and memory growth.

## Requirements

Use macOS, Flutter 3.47.5, Xcode, CocoaPods, the `xcodeproj` Ruby gem, and the
requested iOS Simulator runtimes. The host uses Flutter's current UIScene and
implicit-engine APIs, so it needs a newer toolchain than the package minimum.
The check does not change plugin source or public API.

## Run the checks

Prepare and run 100 engine restarts on the current iOS runtime:

```sh
python3 .github/ci/prepare_ios_stress.py /tmp/candidate.tar.gz /tmp/ios-stress-current \
  --cycles 100 --sha256 <archive-sha256>
python3 .github/ci/run_ios_stress.py /tmp/ios-stress-current \
  --device <current-simulator-udid> --output /tmp/ios-stress-current.json
```

Repeat with a fresh consumer, `--cycles 30`, and the older supported simulator.
The scripts refuse to replace an existing consumer or report. Build and UI-test
logs and an `.xcresult` bundle are saved beside the JSON report.

Use `--collect-only` to collect an interrupted run into a new report path. This
retains the native analysis, but the test exit status remains unknown. A report
without a verified XCUITest result cannot pass the full check.

## Restart and lifecycle criteria

Requests alternate between `platformDefault` and `flutterEngine`; both must
resolve to `flutterEngine`. Each cycle requires fresh Dart state, the same
native PID, saved preferences/file/SQLite markers, working plugin channels,
and a mounted WebView.

Each new WebView must complete boot-specific JavaScript navigation and message
exchange. One scroll request must reach the expected offset within 2 px for
three consecutive animation frames within 2 seconds. Read the offset again
after the fixed 2-second settle interval. Both values and the native WebView
geometry go into the report. Do not issue an extra scroll to make a check pass.

Every 10 cycles, XCUITest presses Home and reactivates the app. Require a real
pause/resume pair and another WebView interaction before continuing. Process
mode must fail at each checkpoint. Initial and final HTTP/image smoke checks
are reported separately.

## Object lifetime and memory

The host forwards each `FlutterEngine.destroyContext` call to the original
method exactly once and records its return. Generated IDs and weak references
track engines, controllers, and WebViews. The host never reads engine
properties after destruction and restores interception at completion. The
plugin's normal engine factory and root-view installer remain in use.

A fixed retained initial implicit-engine wrapper is allowed after its context
is destroyed. Retained replacement objects require investigation.

Compare resident memory and physical footprint medians using these windows:

| Run | Initial window | Final window | Trend blocks |
| --- | --- | --- | --- |
| 100 restarts | Cycles 11-20 | Cycles 81-100 | 10 cycles |
| 30 restarts | Cycles 6-10 | Cycles 21-30 | 5 cycles |

Growth above the larger of 30 MiB or 20%, or continuing monotonic block growth,
fails the check pending investigation. Events are streamed to disk so the host
does not retain a growing history in memory.

## Saved evidence

Each report records archive and canonical payload SHA-256 values, resolved
package root, plugin metadata, dependency versions, verification source hashes,
the fixed settle interval, and every boot. Package files are checked against
the archive manifest before and after the build and run.

These results cover Simulator debug builds. Verify signed device and
distribution behavior separately when host plugins or packaging require it.

To check the evidence evaluator without running an iOS app:

```sh
python3 -m unittest discover -s .github/ci -p test_ios_stress.py
```
