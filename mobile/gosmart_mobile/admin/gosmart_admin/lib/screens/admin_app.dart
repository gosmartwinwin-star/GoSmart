import 'package:flutter/material.dart';
import '../application/ports.dart';
import '../controllers/admin_auth_controller.dart';
import '../controllers/driver_applications_controller.dart';
import 'admin_login_screen.dart';
import 'driver_applications_screen.dart';

final class GoSmartAdminApp extends StatelessWidget {
  const GoSmartAdminApp({
    required this.auth,
    required this.applications,
    super.key,
  });
  final AdminAuthController auth;
  final DriverApplicationAdminReadGateway applications;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'GoSmart Yönetim',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF174A5B),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF4F7F8),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      useMaterial3: true,
    ),
    home: ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (auth.isInitializing) {
          return Scaffold(
            body: Center(
              child: Semantics(
                label: 'Yönetici oturumu kontrol ediliyor',
                child: const CircularProgressIndicator(),
              ),
            ),
          );
        }
        if (auth.session == null) return AdminLoginScreen(controller: auth);
        return AdminShellScreen(auth: auth, gateway: applications);
      },
    ),
  );
}

final class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({
    required this.auth,
    required this.gateway,
    super.key,
  });
  final AdminAuthController auth;
  final DriverApplicationAdminReadGateway gateway;
  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  late final DriverApplicationsController controller;
  @override
  void initState() {
    super.initState();
    controller = DriverApplicationsController(widget.gateway);
    controller.loadInitial();
  }

  @override
  void dispose() {
    controller.clearSensitiveState();
    controller.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    controller.clearSensitiveState();
    await widget.auth.signOut();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GoSmart Yönetim'),
          Text(
            'Sürücü Başvuru İnceleme Paneli',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: _signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Çıkış Yap'),
        ),
        const SizedBox(width: 12),
      ],
    ),
    body: Row(
      children: [
        if (MediaQuery.sizeOf(context).width >= 900)
          const SizedBox(
            width: 220,
            child: ColoredBox(
              color: Color(0xFFE7EFF1),
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ListTile(
                    leading: Icon(Icons.assignment_outlined),
                    title: Text('Sürücü Başvuruları'),
                    selected: true,
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: DriverApplicationsScreen(
            controller: controller,
            gateway: widget.gateway,
          ),
        ),
      ],
    ),
  );
}
