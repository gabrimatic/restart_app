import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:webview_flutter/webview_flutter.dart';

typedef PlatformProbe = ({String name, bool ok, String detail});

Future<List<PlatformProbe>> runPlatformProbes({
  required String bootToken,
  required int dartOnlyDirtyState,
}) async {
  final probes = <PlatformProbe>[];

  Future<void> probe(String name, Future<String> Function() body) async {
    try {
      probes.add((name: name, ok: true, detail: await body()));
    } catch (error) {
      probes.add((name: name, ok: false, detail: '$error'));
    }
  }

  await probe('file storage', () async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/restart_app_example.json');
    await file.writeAsString(jsonEncode({'bootToken': bootToken}));
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (decoded['bootToken'] != bootToken) {
      throw StateError('file roundtrip mismatch');
    }
    return 'ok';
  });

  await probe('sqflite', () async {
    if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      return 'skipped on this platform';
    }

    final db = await openDatabase(
      '${await getDatabasesPath()}/restart_app_example.db',
      version: 1,
      onCreate: (database, version) {
        return database.execute(
          'CREATE TABLE IF NOT EXISTS probe(id INTEGER PRIMARY KEY AUTOINCREMENT, boot TEXT)',
        );
      },
    );
    await db.insert('probe', {'boot': bootToken});
    final rows = await db.query('probe');
    await db.close();
    return 'rows=${rows.length}';
  });

  await probe('device info', () async {
    final plugin = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      return '${info.name}/${info.utsname.machine}';
    }
    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      return '${info.brand}/${info.model}';
    }
    if (Platform.isMacOS) {
      final info = await plugin.macOsInfo;
      return info.model;
    }
    if (Platform.isLinux) {
      final info = await plugin.linuxInfo;
      return info.prettyName;
    }
    if (Platform.isWindows) {
      final info = await plugin.windowsInfo;
      return info.computerName;
    }
    return 'unknown platform';
  });

  await probe('webview', () async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return 'skipped on this platform';
    }

    final controller = WebViewController();
    await controller.loadHtmlString(
      '<html><body><strong>WebView alive after restart</strong></body></html>',
    );
    return 'created';
  });

  return probes;
}

class PlatformPreview extends StatelessWidget {
  const PlatformPreview({super.key});

  @override
  Widget build(BuildContext context) {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return const Text('WebView preview skipped on this platform');
    }

    return const _WebViewPreview();
  }
}

class _WebViewPreview extends StatefulWidget {
  const _WebViewPreview();

  @override
  State<_WebViewPreview> createState() => _WebViewPreviewState();
}

class _WebViewPreviewState extends State<_WebViewPreview> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..loadHtmlString(
        '<html><body><strong>WebView alive after restart</strong></body></html>',
      );
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
