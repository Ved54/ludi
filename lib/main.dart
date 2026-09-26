import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/ludi_theme.dart';
import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only (style guide section 5).
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const LudiApp());
}

class LudiApp extends StatelessWidget {
  const LudiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ludi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: ludiFontFamily,
        scaffoldBackgroundColor: LudiNeutral.boardBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: LudiNeutral.textPrimary,
          primary: LudiNeutral.textPrimary,
          surface: LudiNeutral.surface,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
