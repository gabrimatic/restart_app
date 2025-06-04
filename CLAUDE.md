# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Flutter plugin called `restart_app` that provides cross-platform app restart functionality using native APIs. The plugin supports Android, iOS, and Web platforms with platform-specific implementations.

## Architecture

**Core Structure:**
- `lib/restart_app.dart` - Main Dart API using MethodChannel 'restart'
- `lib/restart_web.dart` - Web-specific implementation 
- `android/src/main/kotlin/gabrimatic/info/restart/RestartPlugin.kt` - Android native implementation
- `ios/Classes/RestartAppPlugin.swift` - iOS native implementation
- `example/` - Demo Flutter app showing plugin usage

**Platform Implementations:**
- **Android**: Uses `Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK` to restart via package manager
- **iOS**: Exits app and sends local notification for user to reopen (due to iOS platform limitations)
- **Web**: Uses `window.location.replace()` to reload the page

**Key Method Channel:**
All platforms communicate through the 'restart' MethodChannel with the `restartApp` method accepting optional parameters:
- `webOrigin` (Web only) - Custom origin URL
- `notificationTitle` (iOS only) - Custom notification title
- `notificationBody` (iOS only) - Custom notification message

## Development Commands

**Flutter Commands:**
```bash
# Run example app
cd example && flutter run

# Run tests
flutter test

# Analyze code
flutter analyze

# Format code
dart format .

# Build for specific platforms
cd example && flutter build apk
cd example && flutter build ios
cd example && flutter build web
```

**Android Development:**
```bash
# Build Android plugin
cd android && ./gradlew build

# Run Android example
cd example && flutter run -d android
```

**iOS Development:**
```bash
# Run iOS example (requires macOS)
cd example && flutter run -d ios

# Build iOS
cd example && flutter build ios
```

## iOS Configuration Requirements

For iOS functionality, the example app's `Info.plist` must include `CFBundleURLTypes` configuration to handle URL schemes for app reopening after restart. This is documented in the README.md.

## Testing

The plugin uses standard Flutter testing. Run tests from the root directory with `flutter test`. The example app serves as an integration test for all platforms.