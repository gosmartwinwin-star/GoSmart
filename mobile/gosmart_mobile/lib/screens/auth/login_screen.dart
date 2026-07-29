import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/primary_button.dart';
import '../home/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController phoneController = TextEditingController();

  @override
  void dispose() {
    phoneController.dispose();
    super.dispose();
  }

  Future<void> verifyPhone() async {
    final phone = phoneController.text.trim();

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Telefon numarasını giriniz."),
        ),
      );
      return;
    }

    // Geçici olarak HomeScreen'e geçiyoruz.
    // Telefon doğrulama daha sonra tekrar eklenecek.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const HomeScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),

              const Icon(
                Icons.local_taxi,
                size: 80,
                color: AppColors.primary,
              ),

              const SizedBox(height: 20),

              const Text(
                "GoSmart",
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                "Akıllı Taksi Platformu",
                style: TextStyle(
                  fontSize: 18,
                  color: AppColors.grey,
                ),
              ),

              const SizedBox(height: 40),

              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: "5XXXXXXXXX",
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              PrimaryButton(
                text: "Devam Et",
                onPressed: verifyPhone,
              ),

              const SizedBox(height: 20),

              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text("veya"),
                  ),
                  Expanded(child: Divider()),
                ],
              ),

              const SizedBox(height: 20),

              OutlinedButton.icon(
                onPressed: () {
                  // Google girişini birazdan ekleyeceğiz.
                },
                icon: const Icon(Icons.login),
                label: const Text("Google ile Giriş Yap"),
              ),

              const Spacer(),

              const Text(
                "© 2026 GoSmart",
                style: TextStyle(
                  color: AppColors.grey,
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}