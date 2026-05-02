import 'package:flutter/widgets.dart';

typedef PlatformProbe = ({String name, bool ok, String detail});

Future<List<PlatformProbe>> runPlatformProbes({
  required String bootToken,
  required int dartOnlyDirtyState,
}) async {
  return [
    (name: 'file storage', ok: true, detail: 'skipped on web'),
    (name: 'sqflite', ok: true, detail: 'skipped on web'),
    (name: 'device info', ok: true, detail: 'skipped on web'),
    (name: 'webview', ok: true, detail: 'skipped on web'),
  ];
}

class PlatformPreview extends StatelessWidget {
  const PlatformPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('Platform preview skipped on web');
  }
}
