import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/firebase/firebase_functions_registry.dart';
import 'firebase_options.dart';
import 'screens/account_deletion_web/account_deletion_web_screen.dart';
import 'services/account_deletion_execution_service.dart';
import 'services/account_deletion_request_service.dart';
import 'services/account_deletion_web_auth_service.dart';

const _appCheckSiteKey = String.fromEnvironment(
  'ACCOUNT_DELETION_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    throw UnsupportedError(
      'The account deletion entrypoint is available only on web.',
    );
  }

  if (_appCheckSiteKey.trim().isEmpty) {
    runApp(const _AccountDeletionWebConfigurationErrorApp());
    return;
  }

  final app = await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await FirebaseAppCheck.instanceFor(
    app: app,
  ).activate(providerWeb: ReCaptchaEnterpriseProvider(_appCheckSiteKey));

  FirebaseFunctionsRegistry.configure(app: app);

  final authService = AccountDeletionWebAuthService(
    auth: FirebaseAuth.instanceFor(app: app),
  );
  final requestService = AccountDeletionRequestService();
  final executionService = AccountDeletionExecutionService();

  runApp(
    AccountDeletionWebApp(
      screen: AccountDeletionWebScreen(
        initialUser: authService.currentUser,
        signInWithGoogle: authService.signInWithGoogle,
        startPhoneSignIn: authService.startPhoneSignIn,
        confirmPhoneCode: authService.confirmPhoneCode,
        requestDeletion: requestService.requestDeletion,
        executeDeletion: executionService.execute,
        signOut: authService.signOut,
      ),
    ),
  );
}

class AccountDeletionWebApp extends StatelessWidget {
  const AccountDeletionWebApp({required this.screen, super.key});

  final Widget screen;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YoldaAl Hesap Silme',
      debugShowCheckedModeBanner: false,
      home: screen,
    );
  }
}

class _AccountDeletionWebConfigurationErrorApp extends StatelessWidget {
  const _AccountDeletionWebConfigurationErrorApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Hesap silme hizmeti şu anda kullanılamıyor. '
              'Lütfen daha sonra tekrar deneyin.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
