import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'application/ports.dart';
import 'controllers/admin_auth_controller.dart';
import 'firebase_options.dart';
import 'infrastructure/firebase_admin_auth_gateway.dart';
import 'infrastructure/firebase_admin_callable_invoker.dart';
import 'screens/admin_app.dart';
import 'services/driver_application_admin_read_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final auth = AdminAuthController(FirebaseAdminAuthGateway());
  final DriverApplicationAdminReadGateway applications =
      DriverApplicationAdminReadService(FirebaseAdminCallableInvoker());
  await auth.initialize();
  runApp(GoSmartAdminApp(auth: auth, applications: applications));
}
