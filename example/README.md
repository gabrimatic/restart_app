# restart_example

Demonstrates how to use `restart_app`.

The example app shows:

- `Restart.restart()` with structured success/error handling
- path URL strategy on web
- opt-in iOS Flutter engine restart setup in `ios/Runner/AppDelegate.swift`

## Running

```bash
flutter pub get
flutter run
```

On iOS, the example configures a custom `FlutterEngine` factory and re-registers plugins with `GeneratedPluginRegistrant` so `RestartMode.platformDefault` can use Flutter engine restart instead of the legacy notification fallback.
