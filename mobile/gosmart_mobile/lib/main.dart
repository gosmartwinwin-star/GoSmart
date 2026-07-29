import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/splash/splash_screen.dart';

void main() {
  runApp(const GoSmartApp());
}

class GoSmartApp extends StatelessWidget {
  const GoSmartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GoSmart',

      // GoSmart Design System Theme
      theme: GoSmartTheme.light(),

      home: const SplashScreen(),
    );
  }
}