import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/primary_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instanceFor(app: Firebase.app());
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController codeController = TextEditingController();

  String? _verificationId;
  bool _isSendingCode = false;
  bool _isCompletingSignIn = false;

  @override
  void dispose() {
    phoneController.dispose();
    codeController.dispose();
    super.dispose();
  }

  Future<void> verifyPhone() async {
    if (_isSendingCode || _isCompletingSignIn) return;

    final phoneNumber = _normalizePhoneNumber(phoneController.text);
    if (phoneNumber == null) {
      _showMessage('Geçerli bir telefon numarası giriniz.');
      return;
    }

    setState(() => _isSendingCode = true);

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (credential) async {
          await _completeSignIn(credential);
        },
        verificationFailed: (error) {
          if (mounted) {
            setState(() => _isSendingCode = false);
            _handleVerificationError(error);
          }
        },
        codeSent: (verificationId, resendToken) {
          if (!mounted || _isCompletingSignIn) return;
          setState(() {
            _verificationId = verificationId;
            _isSendingCode = false;
          });
          _showMessage('Doğrulama kodu gönderildi.');
        },
        codeAutoRetrievalTimeout: (verificationId) {
          if (!mounted || _isCompletingSignIn) return;
          setState(() {
            _verificationId = verificationId;
            _isSendingCode = false;
          });
        },
      );
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() => _isSendingCode = false);
        _handleVerificationError(error);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSendingCode = false);
        _showMessage('Telefon doğrulama işlemi başlatılamadı.');
      }
    }
  }

  Future<void> _verifyCode() async {
    final verificationId = _verificationId;
    final code = codeController.text.trim();

    if (verificationId == null) {
      _showMessage('Önce doğrulama kodu isteyin.');
      return;
    }
    if (code.length != 6) {
      _showMessage('6 haneli doğrulama kodunu giriniz.');
      return;
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: code,
    );
    await _completeSignIn(credential);
  }

  Future<void> _completeSignIn(PhoneAuthCredential credential) async {
    if (_isCompletingSignIn) return;
    _isCompletingSignIn = true;

    if (mounted) {
      setState(() => _isSendingCode = false);
    }

    try {
      await _auth.signInWithCredential(credential);
      final user = _auth.currentUser;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Oturum açılamadı.',
        );
      }
      await user.getIdToken(true);
      // authStateChanges üst düzey yönlendirmeyi güvenli biçimde yapar.
    } on FirebaseAuthException catch (error) {
      _showMessage(_messageForAuthError(error));
      _isCompletingSignIn = false;
      if (mounted) setState(() {});
    } catch (_) {
      _showMessage('Giriş sırasında beklenmeyen bir sorun oluştu.');
      _isCompletingSignIn = false;
      if (mounted) setState(() {});
    }
  }

  String? _normalizePhoneNumber(String rawValue) {
    var value = rawValue.replaceAll(RegExp(r'[\s()-]'), '');
    if (value.startsWith('00')) value = '+${value.substring(2)}';
    if (value.startsWith('0')) value = value.substring(1);
    if (!value.startsWith('+')) value = '+90$value';
    return RegExp(r'^\+[1-9]\d{9,14}$').hasMatch(value) ? value : null;
  }

  String _messageForAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-phone-number':
        return 'Telefon numarası geçerli değil.';
      case 'app-not-authorized':
        return 'Bu Android uygulaması Firebase telefon doğrulaması için '
            'yetkilendirilmemiş.';
      case 'invalid-app-credential':
        return 'Uygulama doğrulaması başarısız oldu. Firebase Android '
            'yapılandırmasını kontrol edin.';
      case 'missing-client-identifier':
        return 'Uygulama doğrulama bilgisi alınamadı.';
      case 'captcha-check-failed':
        return 'Uygulama güvenlik doğrulaması tamamlanamadı.';
      case 'invalid-verification-code':
        return 'Doğrulama kodu hatalı.';
      case 'session-expired':
        return 'Doğrulama süresi doldu. Yeni kod isteyin.';
      case 'too-many-requests':
        return 'Çok fazla doğrulama isteği gönderildi. Lütfen daha sonra '
            'tekrar deneyin.';
      case 'quota-exceeded':
        return 'Telefon doğrulama kotası aşıldı.';
      case 'network-request-failed':
        return 'İnternet bağlantısı kurulamadı.';
      case 'billing-not-enabled':
        return 'Telefon doğrulaması için faturalandırma etkin değil.';
      case 'operation-not-allowed':
        return 'Telefonla giriş bu Firebase projesinde etkin değil.';
      case 'user-disabled':
        return 'Bu kullanıcı hesabı devre dışı bırakılmış.';
      default:
        return 'Telefon doğrulama işlemi tamamlanamadı.';
    }
  }

  void _handleVerificationError(FirebaseAuthException error) {
    if (kDebugMode) {
      debugPrint('Telefon doğrulama hata kodu: ${error.code}');
    }
    final userMessage = _messageForAuthError(error);
    final visibleMessage = kDebugMode
        ? '$userMessage [kod: ${error.code}]'
        : userMessage;
    _showMessage(visibleMessage);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isCodeSent = _verificationId != null;
    final isBusy = _isSendingCode || _isCompletingSignIn;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.sizeOf(context).height - 96,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.local_taxi,
                  size: 80,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 20),
                const Text(
                  'GoSmart',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Akıllı Taksi Platformu',
                  style: TextStyle(fontSize: 18, color: AppColors.grey),
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: phoneController,
                  enabled: !isBusy && !isCodeSent,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: '5XXXXXXXXX',
                    prefixIcon: const Icon(Icons.phone),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                if (isCodeSent) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    enabled: !isBusy,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      hintText: 'SMS doğrulama kodu',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (isBusy)
                  const CircularProgressIndicator()
                else
                  PrimaryButton(
                    text: isCodeSent ? 'Giriş Yap' : 'Devam Et',
                    onPressed: isCodeSent ? _verifyCode : verifyPhone,
                  ),
                if (isCodeSent && !isBusy)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _verificationId = null;
                        codeController.clear();
                      });
                    },
                    child: const Text('Telefon numarasını değiştir'),
                  ),
                const SizedBox(height: 20),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('veya'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.login),
                  label: const Text('Google ile Giriş Yap'),
                ),
                const SizedBox(height: 40),
                const Text(
                  '© 2026 GoSmart',
                  style: TextStyle(color: AppColors.grey),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Auth tanılama v2',
                    style: TextStyle(fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
