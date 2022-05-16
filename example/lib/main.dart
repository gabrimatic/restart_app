import 'package:flutter/material.dart';
import 'package:restart_app/restart_app.dart';

void main() {
  runApp(ExampleApp());
}

class ExampleApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Restart App Example'),
        ),
        body: Center(
          child: TextButton(
            child: Text('Restart!'),
            onPressed: () {
              /// Fill webOrigin only when your new origin is different than the app's origin
              Restart.restartApp();
            },
          ),
        ),
      ),
    );
  }
}
