# restart_app example

Try the default restart behavior, select an explicit restart mode, and see how
the app handles the result.

## Run the app

From this directory:

```sh
flutter pub get
flutter run
```

The example requires Flutter 3.38 and Dart 3.10 or later for its scene APIs and
dependencies. The package itself supports older SDKs; see its
[requirements](https://gabrimatic.github.io/restart_app/quickstart/#requirements). Your Flutter version also determines
which OS versions you can run.

Select **Restart app** to use the platform default. The screen shows which state
survives the restart and whether other Flutter packages remain usable. Other
buttons let you try explicit modes and view errors for unsupported requests.
If saving state or restarting fails, the app displays the error and lets you
try again.

On the web, the example uses path URLs. **Restart with explicit web URL** reloads
the current URL through the `webOrigin` option.

## iOS setup

The example uses Flutter's UIScene lifecycle. Its
[AppDelegate.swift](ios/Runner/AppDelegate.swift) registers plugins on the
initial engine and each replacement engine. Keep the scene manifest in
[Info.plist](ios/Runner/Info.plist) when adapting this setup. It is required when
building with Xcode 27.

**iOS notification fallback** is a separate, explicit action. It requests
notification permission and schedules a notification, then exits only if
scheduling succeeds. The user must reopen the app by tapping the notification.
The normal restart button replaces the Flutter engine within the running process.

For integration in your own app, follow the
[iOS setup guide](https://gabrimatic.github.io/restart_app/product/ios-engine-restart/).

## Contributor checks

The [verification guide](https://github.com/gabrimatic/restart_app/blob/master/.github/ci/verification.md)
describes the automated platform checks, including the separate
`lib/web_restart_probe.dart` entrypoint for JavaScript and WebAssembly builds.
