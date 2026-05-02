import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restart_app/restart_app.dart';
import 'package:restart_app_example/platform_probes.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const _imageUrl = 'https://www.gstatic.com/webp/gallery/1.sm.jpg';

final String restartCheckBootToken =
    DateTime.now().microsecondsSinceEpoch.toString();
int restartCheckDirtyState = 0;

Future<int> markRestartCheckDirtyState() async {
  restartCheckDirtyState += 1;

  final prefs = await SharedPreferences.getInstance();
  final attempts = (prefs.getInt('restartAttempts') ?? 0) + 1;
  await prefs.setInt('restartAttempts', attempts);

  return restartCheckDirtyState;
}

void resetRestartCheckDirtyState() {
  restartCheckDirtyState = 0;
}

class RestartCheckResult {
  const RestartCheckResult(this.name, this.ok, this.detail);

  final String name;
  final bool ok;
  final String detail;
}

class RestartChecksPanel extends StatefulWidget {
  const RestartChecksPanel({super.key, this.runChecksOnStart = true});

  final bool runChecksOnStart;

  @override
  State<RestartChecksPanel> createState() => _RestartChecksPanelState();
}

class _RestartChecksPanelState extends State<RestartChecksPanel> {
  var _summary = 'Running checks...';
  var _launchCount = 0;
  var _restartAttempts = 0;
  var _running = true;
  List<RestartCheckResult> _results = const [];

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

    final results = <RestartCheckResult>[];

    Future<void> probe(String name, Future<String> Function() body) async {
      try {
        final detail = await body().timeout(const Duration(seconds: 12));
        results.add(RestartCheckResult(name, true, detail));
      } catch (error, stackTrace) {
        debugPrint('Restart check failed: $name\n$error\n$stackTrace');
        results.add(RestartCheckResult(name, false, '$error'));
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
      final restartAttempts = prefs.getInt('restartAttempts') ?? 0;
      await prefs.setInt('launchCount', launchCount);

      if (!mounted) {
        return 'launch=$launchCount, restartAttempts=$restartAttempts';
      }

      setState(() {
        _launchCount = launchCount;
        _restartAttempts = restartAttempts;
      });

      return 'launch=$launchCount, restartAttempts=$restartAttempts';
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
        throw StateError('cannot launch HTTPS URL');
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
      final file = await DefaultCacheManager().getSingleFile(_imageUrl);
      return 'bytes=${await file.length()}';
    });

    final platformResults = await runPlatformProbes(
      bootToken: restartCheckBootToken,
      dartOnlyDirtyState: restartCheckDirtyState,
    );
    for (final platformResult in platformResults) {
      results.add(
        RestartCheckResult(
          platformResult.name,
          platformResult.ok,
          platformResult.detail,
        ),
      );
    }

    await probe('dart clean state', () async {
      if (restartCheckDirtyState != 0) {
        throw StateError(
            'dirty state survived restart: $restartCheckDirtyState');
      }
      return 'dirty=0, boot=$restartCheckBootToken';
    });

    if (!mounted) {
      return;
    }

    setState(() {
      _results = results;
      _summary =
          _allPassResults(results) ? 'All checks passed' : 'Some checks failed';
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Package restart checks',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(_summary),
            const SizedBox(height: 8),
            Text('boot token: $restartCheckBootToken'),
            Text('dart dirty state: $restartCheckDirtyState'),
            Text('launches: $_launchCount'),
            Text('restart attempts: $_restartAttempts'),
            const SizedBox(height: 12),
            const _PackagePreview(),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _running ? null : _runChecks,
              child: const Text('Run checks'),
            ),
            const Divider(),
            for (final result in _results)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(result.ok ? Icons.check_circle : Icons.error),
                title: Text('${result.name}: ${result.ok ? 'pass' : 'fail'}'),
                subtitle: Text(result.detail),
              ),
          ],
        ),
      ),
    );
  }
}

class _PackagePreview extends StatelessWidget {
  const _PackagePreview();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SvgPicture.string(
              '<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="7" fill="#1565C0"/></svg>',
              width: 28,
              height: 28,
            ),
            const SizedBox(width: 12),
            CachedNetworkImage(
              imageUrl: _imageUrl,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
            ),
          ],
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 84, child: PlatformPreview()),
      ],
    );
  }
}

bool _allPassResults(List<RestartCheckResult> results) {
  return results.isNotEmpty && results.every((result) => result.ok);
}
