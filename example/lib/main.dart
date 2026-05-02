import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restart_app_example/platform_probes.dart';
import 'package:restart_app/restart_app.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

final String bootToken = DateTime.now().microsecondsSinceEpoch.toString();
int dartOnlyDirtyState = 0;

void main() {
  usePathUrlStrategy();
  runApp(const RestartAppExample());
}

class RestartAppExample extends StatelessWidget {
  const RestartAppExample({super.key, this.runChecksOnStart = true});

  final bool runChecksOnStart;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Restart App Example',
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: HomePage(runChecksOnStart: runChecksOnStart),
    );
  }
}

class ProbeResult {
  const ProbeResult(this.name, this.ok, this.detail);

  final String name;
  final bool ok;
  final String detail;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.runChecksOnStart = true});

  final bool runChecksOnStart;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var _summary = 'Running checks...';
  var _lastRestart = 'none';
  var _launchCount = 0;
  var _engineRestartCount = 0;
  var _running = true;
  List<ProbeResult> _results = const [];

  bool get _allPass =>
      _results.isNotEmpty && _results.every((result) => result.ok);

  @override
  void initState() {
    super.initState();
    if (widget.runChecksOnStart) {
      unawaited(_runChecks());
    } else {
      _summary = 'Checks not started';
      _running = false;
    }
  }

  Future<void> _runChecks() async {
    setState(() {
      _running = true;
      _summary = 'Running checks...';
    });

    final results = <ProbeResult>[];

    Future<void> probe(String name, Future<String> Function() body) async {
      try {
        final detail = await body().timeout(const Duration(seconds: 12));
        results.add(ProbeResult(name, true, detail));
      } catch (error, stackTrace) {
        debugPrint('Probe failed: $name\n$error\n$stackTrace');
        results.add(ProbeResult(name, false, '$error'));
      }
    }

    await probe('restart capability', () async {
      final capability = await Restart.restartCapability();
      return [
        'default=${capability.platformDefaultMode.name}',
        'engine=${capability.flutterEngineRestart}',
        'configured=${capability.engineRestartConfigured}',
      ].join(', ');
    });

    await probe('shared preferences', () async {
      final prefs = await SharedPreferences.getInstance();
      final launchCount = (prefs.getInt('launchCount') ?? 0) + 1;
      final engineRestarts = prefs.getInt('engineRestarts') ?? 0;
      await prefs.setInt('launchCount', launchCount);
      setState(() {
        _launchCount = launchCount;
        _engineRestartCount = engineRestarts;
      });
      return 'launch=$launchCount, engineRestarts=$engineRestarts';
    });

    await probe('package info', () async {
      final info = await PackageInfo.fromPlatform();
      return '${info.appName}/${info.version}';
    });

    await probe('connectivity', () async {
      final states = await Connectivity().checkConnectivity();
      return states.map((state) => state.name).join(',');
    });

    await probe('url launcher', () async {
      final ok = await canLaunchUrl(Uri.parse('https://example.com'));
      if (!ok) {
        throw StateError('cannot launch https URL');
      }
      return 'https ok';
    });

    await probe('http', () async {
      final response = await http.get(Uri.parse('https://example.com'));
      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw StateError('status=${response.statusCode}');
      }
      return 'status=${response.statusCode}';
    });

    await probe('cache manager', () async {
      final file = await DefaultCacheManager().getSingleFile(
        'https://www.gstatic.com/webp/gallery/1.sm.jpg',
      );
      return 'bytes=${await file.length()}';
    });

    final platformProbes = await runPlatformProbes(
      bootToken: bootToken,
      dartOnlyDirtyState: dartOnlyDirtyState,
    );
    for (final platformProbe in platformProbes) {
      results.add(
        ProbeResult(
          platformProbe.name,
          platformProbe.ok,
          platformProbe.detail,
        ),
      );
    }

    await probe('dart clean state', () async {
      if (dartOnlyDirtyState != 0) {
        throw StateError('dirty state survived restart: $dartOnlyDirtyState');
      }
      return 'dirty=0, boot=$bootToken';
    });

    if (!mounted) {
      return;
    }

    setState(() {
      _results = results;
      _summary = _all(results) ? 'All checks passed' : 'Some checks failed';
      _running = false;
    });
  }

  Future<void> _restartEngine() async {
    dartOnlyDirtyState += 1;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        'engineRestarts', (prefs.getInt('engineRestarts') ?? 0) + 1);

    setState(() {
      _lastRestart = 'engine restart requested with dirty=$dartOnlyDirtyState';
    });

    final result = await Restart.restart(mode: RestartMode.flutterEngine);
    if (!result.success && mounted) {
      _showFailure(result);
    }
  }

  Future<void> _notificationFallback() async {
    final result = await Restart.restart(
      mode: RestartMode.notificationFallback,
      notificationTitle: 'Restart App Example',
      notificationBody: 'Tap to reopen the example app.',
    );

    if (!result.success && mounted) {
      _showFailure(result);
    }
  }

  Future<void> _unsupportedProcessMode() async {
    final result = await Restart.restart(mode: RestartMode.process);
    if (!mounted) {
      return;
    }
    setState(() {
      _lastRestart =
          '${result.success}:${result.mode.name}:${result.code ?? 'ok'}';
    });
  }

  void _showFailure(RestartResult result) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(result.message ?? result.code ?? 'Restart failed')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Restart App Example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_summary, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('bootToken: $bootToken'),
          Text('dartDirty: $dartOnlyDirtyState'),
          Text('launches: $_launchCount'),
          Text('engine restarts: $_engineRestartCount'),
          Text('last restart: $_lastRestart'),
          const SizedBox(height: 12),
          Row(
            children: [
              SvgPicture.string(
                '<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="7" fill="#1565C0"/></svg>',
                width: 28,
                height: 28,
              ),
              const SizedBox(width: 12),
              CachedNetworkImage(
                imageUrl: 'https://www.gstatic.com/webp/gallery/1.sm.jpg',
                width: 44,
                height: 44,
                fit: BoxFit.cover,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 84, child: PlatformPreview()),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _running ? null : _runChecks,
            child: const Text('Run checks'),
          ),
          FilledButton(
            onPressed: _allPass ? _restartEngine : null,
            child: const Text('Restart Flutter engine'),
          ),
          OutlinedButton(
            onPressed: _notificationFallback,
            child: const Text('Notification fallback'),
          ),
          TextButton(
            onPressed: _unsupportedProcessMode,
            child: const Text('Unsupported process mode'),
          ),
          const Divider(),
          for (final result in _results)
            ListTile(
              dense: true,
              leading: Icon(result.ok ? Icons.check_circle : Icons.error),
              title: Text('${result.name}: ${result.ok ? 'pass' : 'fail'}'),
              subtitle: Text(result.detail),
            ),
        ],
      ),
    );
  }
}

bool _all(List<ProbeResult> results) {
  return results.isNotEmpty && results.every((result) => result.ok);
}
