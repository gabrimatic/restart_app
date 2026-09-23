---
name: restart-app-ios-engine-restart
description: >-
  Configure or debug restart_app Flutter engine restart on iOS, including
  AppDelegate and UIScene registration, custom native shells, engine factories,
  and explicit notification fallback.
---

# iOS Flutter engine restart

## AppDelegate setup

Inspect the app's existing `AppDelegate.swift`, scene lifecycle, and engine
ownership before editing them. Preserve existing plugin and lifecycle wiring.
Read the [AppDelegate examples](references/host-setup.md) for the matching lifecycle:

- UIScene with `FlutterImplicitEngineDelegate`: retain registration of the
  initial engine in `didInitializeImplicitFlutterEngine` and configure
  registration of replacement engines separately.
- Classic `FlutterAppDelegate`: retain normal initial registration in
  `application(_:didFinishLaunchingWithOptions:)` and add the replacement
  engine callback.
- Custom engine or add-to-app: use `setEngineFactory` only when the host owns
  engine creation, startup, and plugin registration. The package example uses
  the standard UIScene setup; custom hosts must preserve their own ownership.

`RestartAppPlugin.configureEngineRestart` is a Swift API, not a Dart method.
Rebuild the iOS app after editing AppDelegate; hot reload does not apply native changes. Xcode 27 requires UIScene
lifecycle adoption. Updating only the restart callback does not migrate the host.

## Restart behavior

- `Restart.restartApp()` uses the configured engine path on iOS. Explicit
  `RestartMode.flutterEngine` selects the same path. Missing configuration
  returns `IOS_ENGINE_RESTART_NOT_CONFIGURED`; it never falls back implicitly.
- `RestartMode.process` fails with `IOS_PROCESS_RESTART_UNSUPPORTED`.
  `forceKill` has no iOS effect. Do not propose private APIs or an exit/relaunch
  trick to implement automatic process restart.
- Engine restart creates a new engine, runs Dart, registers plugins, replaces
  the Flutter view controller, and destroys the old engine context. The iOS
  process, native globals/singletons, unrelated engines, and native resources
  retained by plugins can survive. Do not promise code-push compatibility or
  native-state reset without testing that integration.
- Save any unsaved changes the app needs to keep before restarting. Request
  restart on the main isolate while the app is active.
  A successful `RestartResult` acknowledges scheduling; factory or swap failures
  after that response are logged natively and cannot change the returned result.

## Failure handling

| Result code | Action |
| --- | --- |
| `IOS_ENGINE_RESTART_NOT_CONFIGURED` | Configure AppDelegate, rebuild, and check capability again. |
| `IOS_APP_NOT_ACTIVE` | Wait for foreground activation and an intentional restart action. |
| `IOS_NO_ACTIVE_WINDOW` | Check scene/window lifecycle or supply the correct `windowProvider`. |
| `IOS_UNSAFE_ROOT_REPLACEMENT` | Supply a host-specific `viewControllerInstaller`; do not overwrite a native shell with a generic Flutter root. |
| `IOS_RESTART_ALREADY_IN_PROGRESS` | Prevent duplicate restart requests. |
| `IOS_PROCESS_RESTART_UNSUPPORTED` | Use configured engine restart if it meets the requested behavior. |

For a custom shell, select the intended scene explicitly. The default installer
expects a `FlutterViewController` at the window root. `beforeRestart` runs before
replacement engine creation; `afterRestart` runs after installation and before
the old engine is destroyed. Keep app-specific cleanup consistent with that order.

## Notification fallback

`RestartMode.notificationFallback` requests notification permission, schedules a
local notification, and closes the app. The user must tap the notification to
reopen it. Select this mode only when that interaction is intended. `notificationFallback` capability does not mean permission
is granted. Handle `NOTIFICATION_DENIED`, `AUTHORIZATION_ERROR`, and
`NOTIFICATION_FAILED` as failed results. Custom title/body alone do not select
this mode. The plugin uses local notifications and needs no push entitlement.

## Verification

Check capability after the host is configured, then test default and explicit
engine restart in the foreground. Confirm a fresh Dart boot, saved
data, working plugin calls/platform views, and a second successful restart.
Inspect native logs if success is returned but the old UI remains. Verify native
state assumptions and code-push behavior in a real release build.
