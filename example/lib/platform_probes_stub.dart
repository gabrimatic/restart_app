import 'package:flutter/widgets.dart';

typedef PlatformProbe = ({String name, bool ok, String detail});

bool get supportsWebViewProbe => false;

Future<List<PlatformProbe>> runPlatformProbes({
  required String bootToken,
  required int dartOnlyDirtyState,
}) async {
  return const [];
}

class PlatformPreview extends StatelessWidget {
  const PlatformPreview({
    super.key,
    required this.bootToken,
    required this.onResult,
  });

  final String bootToken;
  final ValueChanged<PlatformProbe> onResult;

  @override
  Widget build(BuildContext context) {
    return const Text('Platform preview skipped on web');
  }
}
