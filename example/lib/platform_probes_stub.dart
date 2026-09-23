import 'package:flutter/widgets.dart';

typedef PlatformProbe = ({String name, bool ok, String detail});

Future<List<PlatformProbe>> runPlatformProbes({
  required String bootToken,
  required int dartOnlyDirtyState,
}) async {
  return const [];
}

class PlatformPreview extends StatelessWidget {
  const PlatformPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('Platform preview skipped on web');
  }
}
