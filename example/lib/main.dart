import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:restart_app/restart_app.dart';
import 'package:restart_app_example/restart_checks.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: HomePage(runChecksOnStart: runChecksOnStart),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.runChecksOnStart = true});

  final bool runChecksOnStart;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var _lastResult = 'No restart requested yet.';
  var _busy = false;

  Future<void> _restartApp() async {
    await _runRestart(
      pendingMessage: 'Restart requested with Restart.restartApp()',
      restart: Restart.restartApp,
    );
  }

  Future<void> _processRestart() async {
    await _runRestart(
      pendingMessage: 'Process restart requested.',
      restart: () => Restart.restartApp(mode: RestartMode.process),
    );
  }

  Future<void> _engineRestart() async {
    await _runRestart(
      pendingMessage: 'Flutter engine restart requested.',
      restart: () => Restart.restartApp(mode: RestartMode.flutterEngine),
    );
  }

  Future<void> _forceKillRestart() async {
    await _runRestart(
      pendingMessage: 'Force-kill restart requested.',
      restart: () => Restart.restartApp(forceKill: true),
    );
  }

  Future<void> _webOriginRestart() async {
    await _runRestart(
      pendingMessage: 'Restart with explicit web URL requested.',
      restart: () => Restart.restartApp(webOrigin: Uri.base.toString()),
    );
  }

  Future<void> _notificationFallback() async {
    await _runRestart(
      pendingMessage: 'iOS notification fallback requested.',
      restart: () {
        return Restart.restartApp(
          mode: RestartMode.notificationFallback,
          notificationTitle: 'Restart App Example',
          notificationBody: 'Tap to reopen the example app.',
        );
      },
    );
  }

  Future<void> _runRestart({
    required String pendingMessage,
    required Future<RestartResult> Function() restart,
  }) async {
    setState(() {
      _busy = true;
      _lastResult = pendingMessage;
    });

    try {
      await markRestartCheckDirtyState();
      final result = await restart();
      if (!result.success) {
        resetRestartCheckDirtyState();
      }
      if (mounted) {
        setState(() {
          _lastResult = result.success
              ? 'Restart accepted with mode ${result.mode.name}.'
              : '${result.code}: ${result.message}';
        });
      }
    } catch (error) {
      resetRestartCheckDirtyState();
      if (mounted) {
        setState(() => _lastResult = 'Restart failed: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _showCapability() async {
    final capability = await Restart.restartCapability();
    if (!mounted) {
      return;
    }

    setState(() {
      _lastResult = [
        'default=${capability.platformDefaultMode.name}',
        'process=${capability.fullProcessRestart}',
        'engine=${capability.flutterEngineRestart}',
      ].join(', ');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Restart App Example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Default restart',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('Call Restart.restartApp() for the default behavior.'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _restartApp,
            child: const Text('Restart app'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : _processRestart,
            child: const Text('Process restart'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : _engineRestart,
            child: const Text('Engine restart (iOS)'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : _forceKillRestart,
            child: const Text('Force-kill restart (Android)'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : _notificationFallback,
            child: const Text('iOS notification fallback'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : _webOriginRestart,
            child: const Text('Restart with explicit web URL'),
          ),
          TextButton(
            onPressed: _busy ? null : _showCapability,
            child: const Text('Show capability'),
          ),
          const SizedBox(height: 12),
          Text(_lastResult),
          const SizedBox(height: 24),
          RestartChecksPanel(runChecksOnStart: widget.runChecksOnStart),
        ],
      ),
    );
  }
}
