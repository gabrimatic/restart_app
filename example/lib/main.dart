import 'package:flutter/material.dart';
import 'package:restart/restart.dart';

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
            onPressed: Restart.restartApp,
          ),
        ),
      ),
    );
  }
}
