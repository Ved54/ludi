import 'package:flutter/material.dart';

import 'ui/home_screen.dart';

void main() {
  runApp(const LudiApp());
}

class LudiApp extends StatelessWidget {
  const LudiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ludi',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
