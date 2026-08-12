import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

typedef SignOutCallback = Future<void> Function();

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.phoneNumber,
    this.signOut,
  });

  final String? phoneNumber;
  final SignOutCallback? signOut;

  static String maskedPhoneNumber(String? phoneNumber) {
    final value = phoneNumber?.trim() ?? '';
    if (value.isEmpty) return 'Telefon numarası bulunamadı';
    final visibleCount = value.length < 4 ? 1 : 4;
    return '${List.filled(value.length - visibleCount, '•').join()}'
        '${value.substring(value.length - visibleCount)}';
  }

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _signingOut = false;
  String? _errorMessage;

  Future<void> _confirmSignOut() async {
    if (_signingOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text('Oturumunuzu kapatmak istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _signingOut = true;
      _errorMessage = null;
    });
    try {
      final signOut = widget.signOut ??
          () => FirebaseAuth.instanceFor(app: Firebase.app()).signOut();
      await signOut();
      if (mounted) {
        await Navigator.of(context).maybePop();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Çıkış yapılamadı. Bağlantınızı kontrol edip tekrar deneyin.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _signingOut = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.account_circle_rounded, size: 88),
              const SizedBox(height: 16),
              const Text('Telefon numarası', textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(
                ProfileScreen.maskedPhoneNumber(widget.phoneNumber),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_errorMessage case final error?) ...[
                const SizedBox(height: 24),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _signingOut ? null : _confirmSignOut,
                icon: _signingOut
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout_rounded),
                label: Text(_signingOut ? 'Çıkış yapılıyor...' : 'Çıkış Yap'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
