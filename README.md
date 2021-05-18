### Restart app in Flutter

---

*A simple plugin to restart your flutter application WITH NATIVE APIs.*

#### How to use it?

---
**1.  Add the package to pubspec.yaml dependency:**

```yaml
dependencies:
  restart_app: ^1.0.0
```

**2. Import package:**

```dart
import 'package:restart_app/restart_app.dart';
```

**3. Call the restartApp method where ever you want:**

```dart
onPressed: () {
    Restart.restartApp();
}
```
