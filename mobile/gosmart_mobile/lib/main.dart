import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'screens/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (kDebugMode) {
    debugPrint('Firebase çalışma projesi: ${Firebase.app().options.projectId}');
    debugPrint(
      'Firebase seçenek projesi: '
      '${DefaultFirebaseOptions.currentPlatform.projectId}',
    );
  }

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
