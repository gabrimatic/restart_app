import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:restart_app/restart_app.dart';
import 'package:url_strategy/url_strategy.dart';

// Events
abstract class SplashEvent {}

class LoadSplash extends SplashEvent {}

abstract class AppEvent {}

class IncrementCounter extends AppEvent {}

class AddItem extends AppEvent {
  final String item;
  AddItem(this.item);
}

// States
abstract class SplashState {}

class SplashInitial extends SplashState {}

class SplashLoaded extends SplashState {}

class AppState {
  final int counter;
  final List<String> items;

  const AppState({this.counter = 0, this.items = const []});

  AppState copyWith({int? counter, List<String>? items}) {
    return AppState(
      counter: counter ?? this.counter,
      items: items ?? this.items,
    );
  }
}

// Blocs
class SplashBloc extends Bloc<SplashEvent, SplashState> {
  SplashBloc() : super(SplashInitial()) {
    on<LoadSplash>((event, emit) async {
      await Future.delayed(const Duration(milliseconds: 600));
      emit(SplashLoaded());
    });
  }
}

class AppBloc extends Bloc<AppEvent, AppState> {
  AppBloc() : super(const AppState()) {
    on<IncrementCounter>((event, emit) {
      emit(state.copyWith(counter: state.counter + 1));
    });

    on<AddItem>((event, emit) {
      emit(state.copyWith(items: [...state.items, event.item]));
    });
  }
}

void main() {
  setPathUrlStrategy();
  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => SplashBloc()),
        BlocProvider(create: (_) => AppBloc()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: SplashPage(),
    );
  }
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<SplashBloc, SplashState>(
      listener: (context, state) {
        if (state is SplashLoaded) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomePage()),
          );
        }
      },
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const FlutterLogo(size: 100),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => context.read<SplashBloc>().add(LoadSplash()),
                child: const Text('Start App'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Restart App Example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BlocBuilder<AppBloc, AppState>(
              builder: (context, state) => Text(
                'Counter: ${state.counter}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.read<AppBloc>().add(IncrementCounter()),
              child: const Text('Increment Counter'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                final itemName =
                    'Item ${DateTime.now().millisecondsSinceEpoch}';
                context.read<AppBloc>().add(AddItem(itemName));
              },
              child: const Text('Add Item'),
            ),
            const SizedBox(height: 20),
            BlocBuilder<AppBloc, AppState>(
              builder: (context, state) => Text(
                'Items: ${state.items.length}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                Restart.restartApp(
                    // In Web Platform, Fill webOrigin only when your new origin is different than the app's origin
                    // webOrigin: 'http://example.com',
                    );
              },
              child: const Text('Restart App'),
            ),
          ],
        ),
      ),
    );
  }
}
