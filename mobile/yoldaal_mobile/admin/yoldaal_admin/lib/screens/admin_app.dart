import 'package:flutter/material.dart';
import '../application/ports.dart';
import '../application/ride_support_admin_ports.dart';
import '../controllers/admin_auth_controller.dart';
import '../controllers/driver_applications_controller.dart';
import '../controllers/ride_support_cases_controller.dart';
import 'admin_login_screen.dart';
import 'driver_applications_screen.dart';
import 'ride_support_cases_screen.dart';

final class YoldaAlAdminApp extends StatelessWidget {
  const YoldaAlAdminApp({
    required this.auth,
    required this.applications,
    required this.reviews,
    required this.reviewEvents,
    this.supportCases,
    super.key,
  });

  final AdminAuthController auth;
  final DriverApplicationAdminReadGateway applications;
  final DriverApplicationAdminReviewGateway reviews;
  final DriverApplicationReviewEventsGateway reviewEvents;
  final RideSupportAdminReadGateway? supportCases;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'YoldaAl Yönetim',
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
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Yönetici oturumu kontrol ediliyor',
              ),
            ),
          );
        }
        if (auth.session == null) return AdminLoginScreen(controller: auth);
        return AdminShellScreen(
          auth: auth,
          gateway: applications,
          reviews: reviews,
          reviewEvents: reviewEvents,
          supportCases: supportCases,
        );
      },
    ),
  );
}

enum _AdminSection { applications, supportCases }

final class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({
    required this.auth,
    required this.gateway,
    required this.reviews,
    required this.reviewEvents,
    this.supportCases,
    super.key,
  });

  final AdminAuthController auth;
  final DriverApplicationAdminReadGateway gateway;
  final DriverApplicationAdminReviewGateway reviews;
  final DriverApplicationReviewEventsGateway reviewEvents;
  final RideSupportAdminReadGateway? supportCases;

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  late final DriverApplicationsController applicationsController;
  RideSupportCasesController? supportController;
  _AdminSection section = _AdminSection.applications;

  @override
  void initState() {
    super.initState();
    applicationsController = DriverApplicationsController(widget.gateway);
    applicationsController.loadInitial();
    final support = widget.supportCases;
    if (support != null) {
      supportController = RideSupportCasesController(
        support,
        handleAuthFailure: widget.auth.signOut,
      );
    }
  }

  void _select(_AdminSection next) {
    if (section == next) return;
    setState(() => section = next);
    if (next == _AdminSection.supportCases &&
        supportController != null &&
        supportController!.items.isEmpty &&
        !supportController!.isLoading) {
      supportController!.loadInitial();
    }
  }

  @override
  void dispose() {
    applicationsController.clearSensitiveState();
    applicationsController.dispose();
    supportController?.clearSensitiveState();
    supportController?.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    applicationsController.clearSensitiveState();
    supportController?.clearSensitiveState();
    await widget.auth.signOut();
  }

  Widget _content() {
    if (section == _AdminSection.supportCases && supportController != null) {
      return RideSupportCasesScreen(controller: supportController!);
    }
    return DriverApplicationsScreen(
      controller: applicationsController,
      gateway: widget.gateway,
      reviews: widget.reviews,
      reviewEvents: widget.reviewEvents,
      auth: widget.auth,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('YoldaAl Yönetim'),
            Text(
              'Operasyon Paneli',
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
          if (wide)
            SizedBox(
              width: 240,
              child: ColoredBox(
                color: const Color(0xFFE7EFF1),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.assignment_outlined),
                        title: const Text('Sürücü Başvuruları'),
                        selected: section == _AdminSection.applications,
                        onTap: () => _select(_AdminSection.applications),
                      ),
                      if (supportController != null)
                        ListTile(
                          leading: const Icon(Icons.support_agent_outlined),
                          title: const Text('Yolculuk Bildirimleri'),
                          selected: section == _AdminSection.supportCases,
                          onTap: () => _select(_AdminSection.supportCases),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(child: _content()),
        ],
      ),
      bottomNavigationBar: !wide && supportController != null
          ? NavigationBar(
              selectedIndex:
                  section == _AdminSection.applications ? 0 : 1,
              onDestinationSelected: (index) => _select(
                index == 0
                    ? _AdminSection.applications
                    : _AdminSection.supportCases,
              ),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.assignment_outlined),
                  label: 'Başvurular',
                ),
                NavigationDestination(
                  icon: Icon(Icons.support_agent_outlined),
                  label: 'Bildirimler',
                ),
              ],
            )
          : null,
    );
  }
}
