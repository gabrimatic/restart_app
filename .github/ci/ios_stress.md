# iOS lifecycle stress

This gate runs a disposable consumer built from a candidate package archive.
Use macOS with Flutter 3.47.5, Xcode, CocoaPods, the `xcodeproj` Ruby gem,
and the requested iOS Simulator runtimes. The QA host uses Flutter's current
UIScene and implicit-engine APIs; its toolchain requirement is separate from
the package's minimum Flutter version. It changes no plugin source or public
API. Use a fresh consumer directory for each run.

Prepare and run 100 engine restarts on the current iOS runtime:

```sh
python3 .github/ci/prepare_ios_stress.py /tmp/candidate.tar.gz /tmp/ios-stress-current \
  --cycles 100 --sha256 <archive-sha256>
python3 .github/ci/run_ios_stress.py /tmp/ios-stress-current \
  --device <current-simulator-udid> --output /tmp/ios-stress-current.json
```

Repeat with a new consumer, `--cycles 30`, and the older supported simulator.
The scripts refuse to replace an existing consumer or evidence file. Native
build and UI-test logs and an `.xcresult` bundle are saved beside the report.
Use `--collect-only` to collect an interrupted run into a new report path.
Collection-only reports retain the native analysis but cannot pass the full
gate without a verified XCUITest result; their test exit status is unknown.

Each run records the archive and canonical payload SHAs, resolved package root, plugin metadata check,
dependency versions, QA source hashes, fixed 2-second settle interval, and every
boot. Package contents are verified against the archive manifest before and
after builds and the test run. Requests alternate between `platformDefault` and `flutterEngine` and must
resolve to `flutterEngine`. Each cycle checks fresh Dart state, unchanged native PID, persisted
preferences/file/SQLite markers, plugin channels, and a mounted WebView with
boot-specific JavaScript navigation, a measured scroll offset, and message
exchange. A single scroll request must reach the requested offset within 2 px
for three consecutive animation frames within 2 seconds. The same offset is
read again after the fixed settle interval. The report records both values and
native WebView geometry; no extra scroll request is used to make a check pass.
XCUITest presses Home
and reactivates the app every 10 cycles; the app must receive a real pause/resume
pair and use the WebView again before continuing. Process mode must fail at each
checkpoint. Initial and final HTTP/image smoke checks are reported separately.

The disposable host forwards every `FlutterEngine.destroyContext` call to the
original method exactly once and records its return. It uses weak references
and generated IDs for engine, controller, and WebView lifetimes. It never reads
engine properties after destruction and restores interception at completion.
The plugin's normal engine factory and root-view installer remain in use.

The report allows a fixed retained initial implicit-engine wrapper after its
context is destroyed. Retained replacement objects require investigation. It
compares resident memory and physical footprint medians for cycles 11-20 and
81-100, with 10-cycle block trends. The older 30-cycle run compares cycles 6-10
and 21-30, with 5-cycle blocks. Growth above the larger of 30 MiB or 20%, or continuing
monotonic block growth, fails the gate pending investigation. The records are
streamed to disk so the host does not retain a growing event history in memory.

This is a Simulator debug-build lifecycle and memory gate. Verify signed device
and distribution behavior separately when host plugins or packaging require it.

Validate the evidence evaluator without running an iOS app:

```sh
python3 -m unittest discover -s .github/ci -p test_ios_stress.py
```
