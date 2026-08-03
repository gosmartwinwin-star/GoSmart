import 'package:flutter/material.dart';
import '../controllers/admin_auth_controller.dart';

final class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({required this.controller, super.key});
  final AdminAuthController controller;
  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool obscure = true;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!formKey.currentState!.validate() || widget.controller.isSigningIn) {
      return;
    }
    final success = await widget.controller.signIn(email.text, password.text);
    password.clear();
    if (!success && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Form(
                key: formKey,
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.admin_panel_settings_outlined, size: 52),
                      const SizedBox(height: 16),
                      Text(
                        'GoSmart Yönetim',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Sürücü Başvuru İnceleme Paneli',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'E-posta'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'E-posta gereklidir.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: password,
                        obscureText: obscure,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Parola',
                          suffixIcon: IconButton(
                            tooltip: obscure
                                ? 'Parolayı göster'
                                : 'Parolayı gizle',
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(
                              obscure ? Icons.visibility : Icons.visibility_off,
                            ),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Parola gereklidir.'
                            : null,
                      ),
                      if (widget.controller.errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          widget.controller.errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: widget.controller.isSigningIn
                            ? null
                            : _submit,
                        child: widget.controller.isSigningIn
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  semanticsLabel: 'Giriş yapılıyor',
                                ),
                              )
                            : const Text('Giriş Yap'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
