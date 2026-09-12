import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'firebase_bootstrap.dart';
import 'screens/splash/splash_screen.dart';
import 'services/driver_offer_push_hint_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeFirebase();
  registerDriverOfferPushBackgroundHandler();
  await initializeDriverOfferPushHintBridge();

  runApp(const YoldaAlApp());
}

class YoldaAlApp extends StatelessWidget {
  const YoldaAlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'YoldaAl',

      // YoldaAl Design System Theme
      theme: YoldaAlTheme.light(),

      home: const SplashScreen(),
    );
  }
}
