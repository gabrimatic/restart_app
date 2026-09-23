import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:restart_app/restart_app.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _host = MethodChannel('restart_app/stress');
final _boot = DateTime.now().microsecondsSinceEpoch.toString();
var _dirty = 0;

void main() => runApp(const MaterialApp(home: StressPage()));

class StressPage extends StatefulWidget {
  const StressPage({super.key});

  @override
  State<StressPage> createState() => _StressPageState();
}

class _StressPageState extends State<StressPage> with WidgetsBindingObserver {
  var _status = 'STARTING';
  WebViewController? _webView;
  Completer<void>? _webReply;
  Completer<void>? _resumed;
  var _expectedClicks = 1;
  num _webScrollY = 0;
  var _webStableFrames = 0;
  num _webStabilizationMilliseconds = 0;
  Map<String, dynamic>? _webMeasurement;
  var _sawBackground = false;
  final _lifecycle = <String>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_run());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle.add(state.name);
    if (state == AppLifecycleState.paused) _sawBackground = true;
    if (state == AppLifecycleState.resumed && _sawBackground) {
      final resumed = _resumed;
      if (resumed != null && !resumed.isCompleted) resumed.complete();
    }
  }

  void _show(String value) {
    if (mounted) setState(() => _status = value);
  }

  void _require(bool value, String message) {
    if (!value) throw StateError(message);
  }

  num _checkWebMeasurement(Map<String, dynamic> value) {
    _webMeasurement = value;
    _require(value['boot'] == _boot, 'Stale WebView boot');
    _require(value['clicks'] == _expectedClicks, 'WebView click did not run');
    _require(value['hash'] == '#active$_expectedClicks',
        'WebView navigation failed');
    final scrollY = value['scrollY'];
    _require(
        scrollY is num &&
            scrollY.isFinite &&
            (scrollY - _expectedClicks * 120).abs() <= 2,
        'WebView scrollY=$scrollY, requestedY=${_expectedClicks * 120}');
    return scrollY as num;
  }

  Future<void> _webViewCheck() async {
    final controller = WebViewController();
    final reply = Completer<void>();
    _webReply = reply;
    var clicked = false;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.addJavaScriptChannel(
      'StressBridge',
      onMessageReceived: (message) async {
        final pending = _webReply;
        try {
          final value = jsonDecode(message.message) as Map<String, dynamic>;
          if (value['kind'] == 'trace') {
            await _host.invokeMethod<void>('record', {
              'kind': 'webview-trace',
              'boot': _boot,
              'measurement': value,
              'native': await _host.invokeMethod<Map>('snapshot'),
            });
            return;
          }
          if (pending == null || pending.isCompleted) return;
          _webScrollY = _checkWebMeasurement(value);
          final elapsed = value['elapsedMilliseconds'];
          _require(
              value['stabilized'] == true &&
                  value['stableFrames'] is int &&
                  value['stableFrames'] >= 3 &&
                  elapsed is num &&
                  elapsed.isFinite &&
                  elapsed > 0 &&
                  elapsed <= 2000,
              'WebView scroll did not stabilize within 2 seconds');
          _webStableFrames = value['stableFrames'] as int;
          _webStabilizationMilliseconds = elapsed as num;
          pending.complete();
        } catch (error, stack) {
          if (pending != null && !pending.isCompleted) {
            pending.completeError(error, stack);
          } else {
            debugPrint('WebView diagnostic failed: $error');
          }
        }
      },
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) async {
          if (clicked) return;
          clicked = true;
          try {
            await controller
                .runJavaScript("document.getElementById('check').click()");
          } catch (error, stack) {
            if (!reply.isCompleted) reply.completeError(error, stack);
          }
        },
        onWebResourceError: (error) {
          if ((error.isForMainFrame ?? true) && !reply.isCompleted) {
            reply.completeError(StateError(error.description));
          }
        },
      ),
    );
    setState(() => _webView = controller);
    await WidgetsBinding.instance.endOfFrame;
    await Future.wait<void>([
      controller.loadHtmlString('''
<html><head><meta name="viewport" content="width=device-width, initial-scale=1">
<style>body { min-height: 2000px; }</style></head><body><h1>Boot $_boot</h1>
<button id="check" onclick="check()">Use WebView</button>
<script>
let clicks = 0;
let trace = [];
function measure(stage, layout = false) {
  const value = {
    stage: stage, time: performance.now(),
    boot: ${jsonEncode(_boot)}, clicks: clicks,
    hash: location.hash, requestedY: clicks * 120,
    scrollY: window.scrollY
  };
  if (layout) {
    const root = document.scrollingElement || document.documentElement;
    Object.assign(value, {
      viewportHeight: window.innerHeight,
      clientHeight: root.clientHeight, scrollHeight: root.scrollHeight,
      bodyClientHeight: document.body.clientHeight,
      bodyScrollHeight: document.body.scrollHeight
    });
  }
  trace.push(value);
  return value;
}
addEventListener('hashchange', () => measure('hashchange'));
function check() {
  clicks++;
  trace = [];
  const started = performance.now();
  location.hash = 'active' + clicks;
  window.scrollTo(0, clicks * 120);
  measure('after-scroll');
  let frame = 0;
  let stableFrames = 0;
  let completed = false;
  let deadline;
  function finish(stabilized, value) {
    if (completed) return;
    completed = true;
    clearTimeout(deadline);
    StressBridge.postMessage(JSON.stringify({
      kind: 'gate', ...value, stabilized: stabilized,
      stableFrames: stableFrames, elapsedMilliseconds: value.time - started
    }));
    StressBridge.postMessage(JSON.stringify({
      kind: 'trace', boot: ${jsonEncode(_boot)}, clicks: clicks, samples: trace
    }));
  }
  function nextFrame() {
    if (completed) return;
    frame++;
    const value = measure('frame-' + frame, true);
    stableFrames = Math.abs(value.scrollY - clicks * 120) <= 2
      ? stableFrames + 1 : 0;
    if (value.time - started >= 2000) {
      finish(false, value);
    } else if (stableFrames >= 3) {
      finish(true, value);
    } else {
      requestAnimationFrame(nextFrame);
    }
  }
  deadline = setTimeout(() => finish(false, measure('timeout', true)),
    Math.max(0, 2000 - (performance.now() - started)));
  requestAnimationFrame(nextFrame);
}
</script></body></html>
'''),
      reply.future.timeout(const Duration(seconds: 20)),
    ]);
  }

  Future<void> _networkSmoke(int cycle) async {
    final smoke = <String, Object?>{
      'kind': 'network',
      'cycle': cycle,
      'boot': _boot
    };
    try {
      final page = await http
          .get(Uri.parse('https://example.com'))
          .timeout(const Duration(seconds: 20));
      _require(page.statusCode == 200 && page.body.contains('Example Domain'),
          'HTTP smoke failed');
      final image = await http
          .get(Uri.parse('https://www.gstatic.com/webp/gallery/1.sm.jpg'))
          .timeout(const Duration(seconds: 20));
      _require(image.statusCode == 200, 'Image HTTP smoke failed');
      final codec = await ui.instantiateImageCodec(image.bodyBytes);
      final frame = await codec.getNextFrame();
      _require(frame.image.width > 0 && frame.image.height > 0,
          'Image did not decode');
      frame.image.dispose();
      codec.dispose();
      smoke['pass'] = true;
    } catch (error) {
      smoke['pass'] = false;
      smoke['error'] = '$error';
    }
    await _host.invokeMethod<void>('record', smoke);
  }

  Future<void> _run() async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      final config = Map<String, dynamic>.from(
          await _host.invokeMethod<Map>('configuration') ?? {});
      final runID = config['runID'] as String;
      final total = config['cycles'] as int;
      final settleMilliseconds = config['settleMilliseconds'] as int;
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final key = 'stress-$runID';
      final stored = prefs.getString(key);
      final previous =
          stored == null ? null : jsonDecode(stored) as Map<String, dynamic>;
      final cycle = previous == null ? 0 : (previous['cycle'] as int) + 1;
      _require(cycle <= total, 'Unexpected extra boot');
      _require(_dirty == 0, 'Dart dirty state survived');
      _require(previous == null || previous['boot'] != _boot,
          'Boot identity did not change');
      final capability = await Restart.restartCapability();
      _require(
          capability.flutterEngineRestart && capability.engineRestartConfigured,
          'Engine restart is unavailable');

      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$key.json');
      final db = await openDatabase(
        '${await getDatabasesPath()}/$key.db',
        version: 1,
        onCreate: (database, _) => database.execute(
            'CREATE TABLE boots(cycle INTEGER PRIMARY KEY, boot TEXT NOT NULL)'),
      );
      try {
        if (previous != null) {
          final priorFile =
              jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          _require(
              priorFile['boot'] == previous['boot'] &&
                  priorFile['cycle'] == cycle - 1,
              'File marker did not survive');
          final rows = await db
              .query('boots', where: 'cycle = ?', whereArgs: [cycle - 1]);
          _require(rows.length == 1 && rows.single['boot'] == previous['boot'],
              'SQLite marker did not survive');
        }
        final next = {'cycle': cycle, 'boot': _boot};
        await file.writeAsString(jsonEncode(next), flush: true);
        await db.insert('boots', next);
        _require(await prefs.setString(key, jsonEncode(next)),
            'Preference write failed');
      } finally {
        await db.close();
      }

      final info = await PackageInfo.fromPlatform();
      _require(info.packageName == 'info.gabrimatic.restartapp.stress',
          'Wrong consumer package');
      _require((await DeviceInfoPlugin().iosInfo).utsname.machine.isNotEmpty,
          'Device info channel failed');
      _require((await Connectivity().checkConnectivity()).isNotEmpty,
          'Connectivity channel failed');
      _require(await canLaunchUrl(Uri.parse('https://example.com')),
          'URL launcher channel failed');
      await _webViewCheck();
      if (cycle == 0 || cycle == total) await _networkSmoke(cycle);

      if (cycle > 0 && cycle % 10 == 0) {
        final rejection = await Restart.restartApp(mode: RestartMode.process);
        _require(
            !rejection.success &&
                rejection.code == 'IOS_PROCESS_RESTART_UNSUPPORTED',
            'Process mode was not rejected');
        await _host.invokeMethod<void>('record',
            {'kind': 'process-rejected', 'cycle': cycle, 'boot': _boot});
        _resumed = Completer<void>();
        _show('WAIT_BACKGROUND $cycle');
        await _resumed!.future.timeout(const Duration(seconds: 90));
        _expectedClicks = 2;
        _webReply = Completer<void>();
        await Future.wait<void>([
          _webView!.runJavaScript("document.getElementById('check').click()"),
          _webReply!.future.timeout(const Duration(seconds: 20)),
        ]);
        await _host.invokeMethod<void>('record', {
          'kind': 'lifecycle',
          'cycle': cycle,
          'boot': _boot,
          'states': _lifecycle
        });
      }

      await Future<void>.delayed(Duration(milliseconds: settleMilliseconds));
      final settledWebView = jsonDecode(await _webView!
              .runJavaScriptReturningResult(
                  "JSON.stringify(measure('settled', true))") as String)
          as Map<String, dynamic>;
      final settledScrollY = _checkWebMeasurement(settledWebView);
      final snapshot = Map<String, dynamic>.from(
          await _host.invokeMethod<Map>('snapshot') ?? {});
      _require(snapshot['applicationState'] == 'active', 'App is not active');
      _require(snapshot['oldUndestroyedEngines'] == 0,
          'An old engine context was not destroyed');
      await _host.invokeMethod<void>('record', {
        'kind': 'cycle',
        'cycle': cycle,
        'boot': _boot,
        'previousBoot': previous?['boot'],
        'dirty': _dirty,
        'webViewClicks': _expectedClicks,
        'webViewScrollY': _webScrollY,
        'webViewStableFrames': _webStableFrames,
        'webViewStabilizationMilliseconds': _webStabilizationMilliseconds,
        'webViewSettledScrollY': settledScrollY,
        'native': snapshot,
      });
      if (cycle == total) {
        await _host
            .invokeMethod<void>('finish', {'pass': true, 'cycles': total});
        _show('PASS cycles=$total');
        return;
      }
      _dirty = 777;
      _show('RESTARTING $cycle');
      final requestedMode = cycle.isEven
          ? RestartMode.platformDefault
          : RestartMode.flutterEngine;
      await _host.invokeMethod<void>('record', {
        'kind': 'request',
        'cycle': cycle,
        'boot': _boot,
        'requestedMode': requestedMode.name,
      });
      final result = await Restart.restartApp(mode: requestedMode);
      await _host.invokeMethod<void>('record', {
        'kind': 'accepted',
        'cycle': cycle,
        'boot': _boot,
        'requestedMode': requestedMode.name,
        'resolvedMode': result.mode.name,
        'success': result.success,
      });
      _require(result.success, '${result.code}: ${result.message}');
      _require(result.mode == RestartMode.flutterEngine,
          'Wrong resolved restart mode');
    } catch (error, stack) {
      try {
        await _host.invokeMethod<void>('finish', {
          'pass': false,
          'error': '$error',
          'stack': '$stack',
          'boot': _boot,
          'webViewMeasurement': _webMeasurement,
          'native': await _host.invokeMethod<Map>('snapshot'),
        });
      } catch (evidenceError) {
        debugPrint('Evidence write failed: $evidenceError');
      }
      _show('FAIL $error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Restart lifecycle stress')),
        body: Column(children: [
          Text(_status),
          Text('boot=$_boot dirty=$_dirty'),
          if (_webView != null)
            SizedBox(height: 250, child: WebViewWidget(controller: _webView!)),
        ]),
      );
}
