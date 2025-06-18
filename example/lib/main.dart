import 'package:flutter/material.dart';
import 'package:restart_app/restart_app.dart';
import 'package:url_strategy/url_strategy.dart';

void main() {
  setPathUrlStrategy();

  runApp(const MaterialApp(home: SplashPage()));
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final nav = Navigator.of(context);
      await Future.delayed(const Duration(milliseconds: 600));
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: FlutterLogo(size: 64)),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Restart App Example')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Restart App Example',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              const Text(
                'Choose restart type:',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 30),
              FilledButton(
                child: const Text('Standard Restart'),
                onPressed: () {
                  Restart.restartApp(
                    notificationTitle: 'Restarting App',
                    notificationBody: 'Please tap here to open the app again.',
                  );
                },
              ),
              const SizedBox(height: 10),
              FilledButton(
                child: const Text('Restart with Delay (2s)'),
                onPressed: () {
                  Restart.restartApp(
                    delayBeforeRestart: 2000,
                    notificationTitle: 'Restarting in 2 seconds',
                    notificationBody: 'App will restart shortly...',
                  );
                },
              ),
              const SizedBox(height: 10),
              FilledButton(
                child: const Text('Force Kill Restart'),
                onPressed: () {
                  Restart.restartApp(
                    forceKill: true,
                    notificationTitle: 'Force Restarting App',
                    notificationBody:
                        'App will completely restart for better cleanup.',
                  );
                },
              ),
              const SizedBox(height: 10),
              FilledButton(
                child: const Text('Hash URL Test (Web)'),
                onPressed: () {
                  Restart.restartApp(
                    webOrigin: '#/test-route',
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
