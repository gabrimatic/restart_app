import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:webview_flutter/webview_flutter.dart';

typedef PlatformProbe = ({String name, bool ok, String detail});

bool get supportsWebViewProbe => Platform.isAndroid || Platform.isIOS;

Future<List<PlatformProbe>> runPlatformProbes({
  required String bootToken,
  required int dartOnlyDirtyState,
}) async {
  final probes = <PlatformProbe>[];

  Future<void> probe(String name, Future<String> Function() body) async {
    try {
      final detail = await body().timeout(const Duration(seconds: 12));
      probes.add((name: name, ok: true, detail: detail));
    } catch (error) {
      probes.add((name: name, ok: false, detail: '$error'));
    }
  }

  await probe('file storage', () async {
    final prefs = await SharedPreferences.getInstance();
    final previousBoot = prefs.getString('restartFileBoot');
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/restart_app_example.json');
    if (previousBoot != null) {
      final previous =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (previous['bootToken'] != previousBoot &&
          previous['bootToken'] != bootToken) {
        throw StateError('Previous boot file did not survive restart.');
      }
    }
    await file.writeAsString(jsonEncode({'bootToken': bootToken}), flush: true);
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (decoded['bootToken'] != bootToken) {
      throw StateError('file roundtrip mismatch');
    }
    if (!await prefs.setString('restartFileBoot', bootToken)) {
      throw StateError('Could not save the file verification marker.');
    }
    return previousBoot == null
        ? 'first boot stored'
        : 'previous boot verified; current boot stored';
  });

  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    await probe('sqflite', () async {
      final prefs = await SharedPreferences.getInstance();
      final previousBoot = prefs.getString('restartDatabaseBoot');
      final db = await openDatabase(
        '${await getDatabasesPath()}/restart_app_example.db',
        version: 1,
        onCreate: (database, version) {
          return database.execute(
            'CREATE TABLE IF NOT EXISTS probe(id INTEGER PRIMARY KEY AUTOINCREMENT, boot TEXT)',
          );
        },
      );
      try {
        if (previousBoot != null) {
          final previousRows = await db.query(
            'probe',
            where: 'boot = ?',
            whereArgs: [previousBoot],
            limit: 1,
          );
          if (previousRows.isEmpty) {
            throw StateError(
              'Previous boot database row did not survive restart.',
            );
          }
        }
        await db.insert('probe', {'boot': bootToken});
        final rows = await db.query(
          'probe',
          where: 'boot = ?',
          whereArgs: [bootToken],
        );
        if (rows.isEmpty) {
          throw StateError('Missing row for the current boot.');
        }
        if (!await prefs.setString('restartDatabaseBoot', bootToken)) {
          throw StateError('Could not save the database verification marker.');
        }
        return previousBoot == null
            ? 'first boot stored'
            : 'previous boot verified; current boot stored';
      } finally {
        await db.close();
      }
    });
  }

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

  return probes;
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
    if (!supportsWebViewProbe) {
      return const Text('WebView preview skipped on this platform');
    }

    return _WebViewPreview(bootToken: bootToken, onResult: onResult);
  }
}

class _WebViewPreview extends StatefulWidget {
  const _WebViewPreview({required this.bootToken, required this.onResult});

  final String bootToken;
  final ValueChanged<PlatformProbe> onResult;

  @override
  State<_WebViewPreview> createState() => _WebViewPreviewState();
}

class _WebViewPreviewState extends State<_WebViewPreview> {
  late final WebViewController _controller;
  var _reported = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    unawaited(_initialize());
  }

  void _report(bool ok, String detail) {
    if (!mounted || _reported) return;
    _reported = true;
    widget.onResult((name: 'webview', ok: ok, detail: detail));
  }

  Future<void> _initialize() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.addJavaScriptChannel(
        'RestartProbe',
        onMessageReceived: (message) {
          if (message.message != widget.bootToken) {
            _report(false, 'WebView returned a stale boot token.');
            return;
          }
          _report(
            true,
            'mounted view and JavaScript roundtrip: ${widget.bootToken}',
          );
        },
      );
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            try {
              await _controller.runJavaScript(
                "document.getElementById('check').click();",
              );
            } catch (error) {
              _report(false, '$error');
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              _report(false, error.description);
            }
          },
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await _controller.loadHtmlString('''
<html><body>
<strong id="status">WebView ready</strong>
<button id="check" onclick="document.getElementById('status').textContent = 'WebView verified'; RestartProbe.postMessage(boot)">Verify</button>
<script>const boot = ${jsonEncode(widget.bootToken)};</script>
</body></html>
''');
    } catch (error) {
      _report(false, '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
