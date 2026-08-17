import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../application/auth/authenticated_landing_resolver.dart';
import '../../core/branding/gosmart_slogans.dart';
import '../../infrastructure/firestore/repositories/firestore_driver_profile_repository.dart';

import '../auth/login_screen.dart';
import '../driver/driver_center_screen.dart';
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
  late Future<AuthenticatedLanding> _landing;

  @override
  void initState() {
    super.initState();
    _landing = _loadLanding(widget.user);
  }

  @override
  void didUpdateWidget(covariant _AuthenticatedSessionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _landing = _loadLanding(widget.user);
    }
  }

  Future<AuthenticatedLanding> _loadLanding(User user) async {
    await user.getIdToken(true);
    return AuthenticatedLandingResolver(
      profiles: FirestoreDriverProfileRepository(),
    ).resolve(user.uid);
  }

  void _retry() {
    setState(() {
      _landing = _loadLanding(widget.user);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthenticatedLanding>(
      future: _landing,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SplashLoadingView();
        }

        if (snapshot.hasError) {
          if (kDebugMode) {
            debugPrint(
              'Oturum a\u00e7\u0131l\u0131\u015f rol\u00fc belirlenemedi.',
            );
          }

          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Oturum bilgileri y\u00fcklenemedi. '
                      '\u0130nternet ba\u011flant\u0131n\u0131z\u0131 '
                      'kontrol edip tekrar deneyin.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tekrar Dene'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return switch (snapshot.data) {
          AuthenticatedLanding.driver => const DriverCenterScreen(),
          AuthenticatedLanding.passenger => const HomeScreen(),
          null => const _SplashLoadingView(),
        };
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
