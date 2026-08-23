import 'package:flutter/material.dart';

import 'game_screen.dart';

// TODO(Aditi): real home screen design (A6).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ludi')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const GameScreen()),
          ),
          child: const Text('Play'),
        ),
      ),
    );
  }
}
