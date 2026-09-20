import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../application/auth/auth_transition_hold.dart';
import '../../application/auth/google_sign_in_coordinator.dart';
import '../../services/google_sign_in_service.dart';

import '../../core/colors/yoldaal_colors.dart';
import '../../widgets/primary_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instanceFor(app: Firebase.app());
  late final GoogleSignInCoordinator _googleSignInCoordinator;
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController codeController = TextEditingController();

  String? _verificationId;
  bool _isSendingCode = false;
  bool _isCompletingSignIn = false;
  bool _isGoogleSignIn = false;
  bool _googlePhoneLinkPending = false;
  bool _googleAutoVerificationInProgress = false;
  bool _phoneVerificationThrottled = false;
  String? _googlePhoneLinkRuntimeCode;

  @override
  void initState() {
    super.initState();
    _googleSignInCoordinator = buildProductionGoogleSignInCoordinator(
      auth: _auth,
    );
  }

  @override
  void dispose() {
    phoneController.dispose();
    codeController.dispose();
    super.dispose();
  }

  Future<void> verifyPhone() async {
    if (_isSendingCode || _isCompletingSignIn || _isGoogleSignIn) {
      return;
    }

    if (_phoneVerificationThrottled) {
      _recordGooglePhoneLinkRuntimeState('phone_verification_throttled');
      if (mounted) setState(() {});
      _showMessage(_googlePhoneLinkRuntimeMessage()!);
      return;
    }

    final phoneNumber = _normalizePhoneNumber(phoneController.text);
    if (phoneNumber == null) {
      _showMessage('Geçerli bir telefon numarası giriniz.');
      return;
    }

    final googlePhoneLinkRequest = _googlePhoneLinkPending;

    setState(() {
      _isSendingCode = true;

      if (googlePhoneLinkRequest) {
        _recordGooglePhoneLinkRuntimeState('phone_verification_requesting');
      }
    });

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (credential) async {
          if (googlePhoneLinkRequest && !_googlePhoneLinkPending) return;

          final googleAutoVerification = googlePhoneLinkRequest;

          if (mounted && googleAutoVerification) {
            setState(() {
              _googleAutoVerificationInProgress = true;
              _recordGooglePhoneLinkRuntimeState('auto_verification_linking');
            });
          }

          try {
            await _completeSignIn(credential);
          } finally {
            if (mounted && googleAutoVerification) {
              setState(() {
                _googleAutoVerificationInProgress = false;
              });
            }
          }
        },
        verificationFailed: (error) {
          if (!mounted) return;
          if (googlePhoneLinkRequest && !_googlePhoneLinkPending) return;

          setState(() {
            _isSendingCode = false;
            _recordPhoneVerificationFailure(error);
          });

          _handleVerificationError(error);
        },
        codeSent: (verificationId, resendToken) {
          if (!mounted || _isCompletingSignIn) return;
          if (googlePhoneLinkRequest && !_googlePhoneLinkPending) return;

          setState(() {
            _verificationId = verificationId;
            _isSendingCode = false;

            if (googlePhoneLinkRequest) {
              _recordGooglePhoneLinkRuntimeState('manual_code_required');
            }
          });

          _showMessage('Doğrulama kodu gönderildi.');
        },
        codeAutoRetrievalTimeout: (verificationId) {
          if (!mounted || _isCompletingSignIn) return;
          if (googlePhoneLinkRequest && !_googlePhoneLinkPending) return;

          setState(() {
            _verificationId = verificationId;
            _isSendingCode = false;

            if (googlePhoneLinkRequest) {
              _recordGooglePhoneLinkRuntimeState('manual_code_required');
            }
          });
        },
      );
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() {
          _isSendingCode = false;
          _recordPhoneVerificationFailure(error);
        });

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

    final googleLinkWasPending = _googlePhoneLinkPending;

    var phoneSessionOpened = false;

    _isCompletingSignIn = true;

    if (mounted) {
      setState(() => _isSendingCode = false);
    }

    if (googleLinkWasPending) {
      authTransitionHold.begin();
    }

    try {
      await _auth.signInWithCredential(credential);
      phoneSessionOpened = true;

      final user = _auth.currentUser;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Oturum açılamadı.',
        );
      }

      if (googleLinkWasPending) {
        await _googleSignInCoordinator.linkPendingAfterPhoneSignIn();
        _googlePhoneLinkPending = false;
      }

      await user.getIdToken(true);

      if (googleLinkWasPending) {
        _recordGooglePhoneLinkRuntimeState('link_succeeded');
        authTransitionHold.release();
      }
    } on GoogleSignInFlowException catch (error) {
      if (googleLinkWasPending) {
        _recordGooglePhoneLinkRuntimeState(error.code);
        if (phoneSessionOpened) {
          await _abortGooglePhoneLink();
        } else {
          // No authenticated phone session exists yet.
          // Release the root gate but keep the pending Google
          // credential so the user can retry phone verification.
          authTransitionHold.release();
        }
      }

      if (mounted) {
        _showMessage(_messageForGoogleLinkRuntimeError(error));
      }

      _isCompletingSignIn = false;

      if (mounted) setState(() {});
    } on FirebaseAuthException catch (error) {
      if (googleLinkWasPending) {
        _recordGooglePhoneLinkRuntimeState('phone_sign_in_failed');

        if (phoneSessionOpened) {
          await _abortGooglePhoneLink();
        } else {
          // No authenticated phone session exists yet.
          // Release the root gate but keep the pending Google
          // credential so the user can retry phone verification.
          authTransitionHold.release();
        }
      }

      if (mounted) {
        _showMessage(_messageForAuthError(error));
      }

      _isCompletingSignIn = false;

      if (mounted) setState(() {});
    } catch (_) {
      if (googleLinkWasPending) {
        _recordGooglePhoneLinkRuntimeState('link_unexpected');

        if (phoneSessionOpened) {
          await _abortGooglePhoneLink();
        } else {
          // No authenticated phone session exists yet.
          // Release the root gate but keep the pending Google
          // credential so the user can retry phone verification.
          authTransitionHold.release();
        }
      }

      if (mounted) {
        _showMessage('Giriş sırasında beklenmeyen bir sorun oluştu.');
      }

      _isCompletingSignIn = false;

      if (mounted) setState(() {});
    }
  }

  void _recordGooglePhoneLinkRuntimeState(String code) {
    _googlePhoneLinkRuntimeCode = code;

    if (kDebugMode) {
      debugPrint('Google phone-link safe state: $code');
    }
  }

  void _recordPhoneVerificationFailure(FirebaseAuthException error) {
    if (error.code == 'too-many-requests') {
      _phoneVerificationThrottled = true;
      _recordGooglePhoneLinkRuntimeState('phone_verification_throttled');
      return;
    }

    if (_googlePhoneLinkPending) {
      _recordGooglePhoneLinkRuntimeState('phone_verification_failed');
    }
  }

  String? _googlePhoneLinkRuntimeMessage() {
    final code = _googlePhoneLinkRuntimeCode;

    if (code == null) return null;

    switch (code) {
      case 'phone_verification_required':
        return 'Google hesabınızı bağlamak için mevcut YoldaAl telefon '
            'hesabınızı doğrulayın.';
      case 'phone_verification_requesting':
        return 'Telefon doğrulaması başlatılıyor.';
      case 'manual_code_required':
        return 'SMS doğrulama kodunu girerek Google hesabı bağlantısını '
            'tamamlayın.';
      case 'auto_verification_linking':
        return 'Telefon numaranız otomatik doğrulandı. '
            'Google hesabınız bağlanıyor.';
      case 'link_succeeded':
        return 'Telefon hesabınız doğrulandı ve Google hesabınız bağlandı.';
      case 'direct_google_signed_in':
        return 'Google hesabınız zaten bağlı. Giriş tamamlanıyor.';
      case 'phone_verification_throttled':
        return 'Çok fazla doğrulama isteği gönderildi. '
            'Yeni SMS isteği bu oturumda durduruldu. '
            'Lütfen daha sonra uygulamayı yeniden açıp tekrar deneyin.';
      case 'phone_verification_failed':
        return 'Telefon doğrulaması tamamlanamadı. '
            'Gösterilen hata mesajını kontrol edin.';
      case 'phone_sign_in_failed':
        return 'Telefon oturumu tamamlanamadı. '
            'Google hesabı bağlantısı yapılmadı.';
      case 'link_unexpected':
        return 'Google hesabı bağlanırken beklenmeyen bir sorun oluştu.';
      default:
        return _messageForGoogleLinkRuntimeError(
          GoogleSignInFlowException(code),
        );
    }
  }

  String _messageForGoogleLinkRuntimeError(GoogleSignInFlowException error) {
    switch (error.code) {
      case 'google_account_link_credential_in_use':
        return 'Bu Google hesabı başka bir YoldaAl hesabına bağlı.';
      case 'google_account_link_account_conflict':
        return 'Bu Google hesabı farklı bir oturum yöntemiyle kullanılıyor.';
      case 'google_account_already_linked':
        return 'Google hesabı zaten bağlı görünüyor. Google ile yeniden giriş yapın.';
      case 'google_account_link_network_failed':
        return 'Google hesabı bağlanırken ağ bağlantısı kesildi. Tekrar deneyin.';
      case 'google_account_link_not_allowed':
        return 'Google hesabı bağlantısı şu anda kullanılamıyor.';
      case 'google_account_link_invalid_credential':
        return 'Google oturumu geçersizleşti. Google ile yeniden devam edin.';
      case 'google_account_link_reauth_required':
        return 'Hesap bağlantısını tamamlamak için yeniden giriş gerekiyor.';
      case 'google_account_link_user_disabled':
        return 'Bu YoldaAl hesabı kullanıma kapalı.';
      case 'google_account_link_internal':
        return 'Google hesabı bağlanırken geçici bir hata oluştu.';
      default:
        return _messageForGoogleError(error);
    }
  }

  Future<void> _abortGooglePhoneLink() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Keep the global transition hold active.
      // If sign-out cannot be proven, authenticated landing
      // must remain fail-closed until process restart/recovery.
      return;
    }

    _verificationId = null;
    codeController.clear();
    _googlePhoneLinkPending = false;
    _googleSignInCoordinator.clearPendingLink();
    authTransitionHold.release();
  }

  Future<void> _startGoogleSignIn() async {
    if (_phoneVerificationThrottled) {
      _recordGooglePhoneLinkRuntimeState('phone_verification_throttled');
      if (mounted) setState(() {});
      _showMessage(_googlePhoneLinkRuntimeMessage()!);
      return;
    }

    if (_isSendingCode ||
        _isCompletingSignIn ||
        _isGoogleSignIn ||
        _googlePhoneLinkPending ||
        authTransitionHold.isHeld) {
      return;
    }

    _googlePhoneLinkPending = false;

    setState(() {
      _isGoogleSignIn = true;
      _googlePhoneLinkRuntimeCode = null;
    });

    try {
      final result = await _googleSignInCoordinator.start();

      if (!mounted) return;

      switch (result.disposition) {
        case GoogleSignInStartDisposition.signedIn:
          _googlePhoneLinkPending = false;
          _recordGooglePhoneLinkRuntimeState('direct_google_signed_in');
          break;
        case GoogleSignInStartDisposition.phoneVerificationRequired:
          _googlePhoneLinkPending = true;
          _verificationId = null;
          codeController.clear();
          _recordGooglePhoneLinkRuntimeState('phone_verification_required');
          _showMessage(
            'Google hesabınızı YoldaAl hesabınıza '
            'bağlamak için telefon numaranızı doğrulayın.',
          );
          break;
      }
    } on GoogleSignInFlowException catch (error) {
      _recordGooglePhoneLinkRuntimeState(error.code);

      if (mounted) {
        _showMessage(_messageForGoogleError(error));
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Google ile giriş şu anda kullanılamıyor.');
      }
    } finally {
      if (mounted) {
        setState(() => _isGoogleSignIn = false);
      }
    }
  }

  String _messageForGoogleError(GoogleSignInFlowException error) {
    return switch (error.code) {
      'google_signin_cancelled' => 'Google ile giriş iptal edildi.',
      'google_auth_unavailable' =>
        'Google ile giriş bu cihazda kullanılamıyor.',
      'google_provider_unavailable' => 'Google hesabına bağlanılamadı.',
      'google_link_state_unavailable' =>
        'Google ile giriş henüz kullanılamıyor.',
      'google_account_link_failed' =>
        'Google hesabı telefon hesabınıza bağlanamadı.',
      'phone_session_missing' => 'Telefon doğrulama oturumu bulunamadı.',
      _ => 'Google ile giriş tamamlanamadı.',
    };
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
    final isBusy = _isSendingCode || _isCompletingSignIn || _isGoogleSignIn;
    final googlePhoneLinkRuntimeMessage = _googlePhoneLinkRuntimeMessage();

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
                  color: YoldaAlColors.primary,
                ),
                const SizedBox(height: 20),
                const Text(
                  'YoldaAl',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ortak Yol Ortak Kazanç',
                  style: TextStyle(fontSize: 18, color: YoldaAlColors.textSecondary),
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
                if (googlePhoneLinkRuntimeMessage != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          if (_googleAutoVerificationInProgress) ...[
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Text(
                            googlePhoneLinkRuntimeMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (kDebugMode &&
                              _googlePhoneLinkRuntimeCode != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Güvenli durum: $_googlePhoneLinkRuntimeCode',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 10,
                                color: YoldaAlColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
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
                    onPressed: isCodeSent
                        ? _verifyCode
                        : (_phoneVerificationThrottled ? null : verifyPhone),
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
                  onPressed:
                      isBusy ||
                          _googlePhoneLinkPending ||
                          _phoneVerificationThrottled
                      ? null
                      : _startGoogleSignIn,
                  icon: const Icon(Icons.account_circle_outlined),
                  label: const Text('Google ile Giriş Yap'),
                ),
                const SizedBox(height: 40),
                const Text(
                  '© 2026 YoldaAl',
                  style: TextStyle(color: YoldaAlColors.textSecondary),
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
