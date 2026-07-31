import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/branding/gosmart_slogans.dart';

import '../auth/login_screen.dart';
import '../home/home_screen.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instanceFor(app: Firebase.app()).authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashLoadingView();
        }

        if (snapshot.hasError) {
          if (kDebugMode) {
            debugPrint('Kimlik doğrulama durumu okunamadı.');
          }
          return const LoginScreen();
        }

        final isSignedIn = snapshot.data != null;
        if (kDebugMode) {
          debugPrint(
            isSignedIn
                ? 'Kimlik doğrulama durumu: oturum açık.'
                : 'Kimlik doğrulama durumu: oturum kapalı.',
          );
        }

        return isSignedIn
            ? _AuthenticatedSessionGate(user: snapshot.data!)
            : const LoginScreen();
      },
    );
  }
}

class _AuthenticatedSessionGate extends StatefulWidget {
  final User user;

  const _AuthenticatedSessionGate({required this.user});

  @override
  State<_AuthenticatedSessionGate> createState() =>
      _AuthenticatedSessionGateState();
}

class _AuthenticatedSessionGateState extends State<_AuthenticatedSessionGate> {
  late Future<void> _refreshToken;

  @override
  void initState() {
    super.initState();
    _refreshToken = widget.user.getIdToken(true);
  }

  @override
  void didUpdateWidget(covariant _AuthenticatedSessionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _refreshToken = widget.user.getIdToken(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _refreshToken,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SplashLoadingView();
        }
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Oturum doğrulanamadı. İnternet bağlantınızı kontrol edip '
                  'uygulamayı yeniden açın.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return const HomeScreen();
      },
    );
  }
}

class _SplashLoadingView extends StatelessWidget {
  const _SplashLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_taxi, size: 90, color: Colors.amber),
            SizedBox(height: 20),
            Text(
              'GoSmart',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              GoSmartSlogans.brand,
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 40),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
