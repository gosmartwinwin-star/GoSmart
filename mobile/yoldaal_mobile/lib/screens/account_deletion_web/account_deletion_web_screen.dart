import 'package:flutter/material.dart';

import '../../services/account_deletion_execution_service.dart';
import '../../services/account_deletion_web_auth_service.dart';

typedef AccountDeletionWebGoogleSignInCallback =
    Future<AccountDeletionWebAuthUser> Function();
typedef AccountDeletionWebPhoneStartCallback =
    Future<void> Function(String phoneNumber);
typedef AccountDeletionWebPhoneConfirmCallback =
    Future<AccountDeletionWebAuthUser> Function(String verificationCode);
typedef AccountDeletionWebRequestCallback = Future<void> Function();
typedef AccountDeletionWebExecutionCallback =
    Future<AccountDeletionExecutionResult> Function();
typedef AccountDeletionWebSignOutCallback = Future<void> Function();

class AccountDeletionWebScreen extends StatefulWidget {
  const AccountDeletionWebScreen({
    required this.signInWithGoogle,
    required this.startPhoneSignIn,
    required this.confirmPhoneCode,
    required this.requestDeletion,
    required this.executeDeletion,
    required this.signOut,
    this.initialUser,
    super.key,
  });

  final AccountDeletionWebAuthUser? initialUser;
  final AccountDeletionWebGoogleSignInCallback signInWithGoogle;
  final AccountDeletionWebPhoneStartCallback startPhoneSignIn;
  final AccountDeletionWebPhoneConfirmCallback confirmPhoneCode;
  final AccountDeletionWebRequestCallback requestDeletion;
  final AccountDeletionWebExecutionCallback executeDeletion;
  final AccountDeletionWebSignOutCallback signOut;

  @override
  State<AccountDeletionWebScreen> createState() =>
      _AccountDeletionWebScreenState();
}

class _AccountDeletionWebScreenState extends State<AccountDeletionWebScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  AccountDeletionWebAuthUser? _user;
  bool _busy = false;
  bool _phoneCodeSent = false;
  bool _identityConfirmed = false;
  bool _deletionDialogOpen = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _user = widget.initialUser;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _googleSignIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _identityConfirmed = false;
    });

    try {
      final user = await widget.signInWithGoogle();
      if (!mounted) return;
      setState(() {
        _user = user;
        _phoneCodeSent = false;
        _message = 'Google hesabı doğrulandı.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Google ile giriş tamamlanamadı. Lütfen tekrar deneyin.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _startPhoneSignIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _identityConfirmed = false;
    });

    try {
      await widget.startPhoneSignIn(_phoneController.text);
      if (!mounted) return;
      setState(() {
        _phoneCodeSent = true;
        _message = 'Doğrulama kodu gönderildi.';
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _message =
            'Telefon numarasını ülke koduyla girin. Örnek: +905551234567';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Telefon doğrulaması başlatılamadı. Lütfen tekrar deneyin.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _confirmPhoneCode() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _identityConfirmed = false;
    });

    try {
      final user = await widget.confirmPhoneCode(_codeController.text);
      if (!mounted) return;
      setState(() {
        _user = user;
        _phoneCodeSent = false;
        _codeController.clear();
        _message = 'Telefon numarası doğrulandı.';
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _message = 'Doğrulama kodunu kontrol edin.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Telefon doğrulaması tamamlanamadı. Lütfen tekrar deneyin.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _manualSignOut() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      await widget.signOut();
      if (!mounted) return;
      setState(() {
        _user = null;
        _identityConfirmed = false;
        _phoneCodeSent = false;
        _message = 'Oturum kapatıldı.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Oturum kapatılamadı. Lütfen tekrar deneyin.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _confirmAndDelete() async {
    if (_busy || _deletionDialogOpen || _user == null || !_identityConfirmed) {
      return;
    }

    _deletionDialogOpen = true;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Hesabı kalıcı olarak sil'),
          content: const Text(
            'Bu işlem kalıcıdır ve geri alınamaz. '
            'Aktif veya tamamlanmamış bir yolculuk varsa silme işlemi '
            'güvenlik nedeniyle engellenebilir. Devam etmek istiyor musunuz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              key: const ValueKey('account-deletion-web-confirm-delete'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Kalıcı olarak sil'),
            ),
          ],
        );
      },
    );
    _deletionDialogOpen = false;

    if (confirmed != true || !mounted || _busy) return;

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      try {
        await widget.requestDeletion();
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _message =
              'Hesap silme isteği başlatılamadı. Oturumunuz açık kaldı; '
              'lütfen tekrar deneyin.';
        });
        return;
      }

      final result = await widget.executeDeletion();

      if (result.status == AccountDeletionExecutionStatus.processing) {
        if (!mounted) return;
        setState(() {
          _message =
              'Hesap silme işlemi devam ediyor. Oturumunuz açık tutuldu; '
              'daha sonra tekrar deneyebilirsiniz.';
        });
        return;
      }

      try {
        await widget.signOut();
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _user = null;
          _identityConfirmed = false;
          _message =
              'Hesap silme işlemi tamamlandı ancak yerel oturum kapatma '
              'işlemi doğrulanamadı. Bu sayfayı kapatın.';
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _user = null;
        _identityConfirmed = false;
        _phoneCodeSent = false;
        _message = 'Hesabınız kalıcı olarak silindi ve oturum kapatıldı.';
      });
    } on AccountDeletionExecutionException catch (error) {
      if (!mounted) return;
      final activeRide =
          error.reason == 'active_ride_blocks_account_deletion' ||
          error.reason == 'non_terminal_ride_blocks_account_deletion';
      setState(() {
        _message = activeRide
            ? 'Aktif veya tamamlanmamış yolculuğunuz bitmeden hesabınızı '
                  'silemezsiniz. Oturumunuz açık kaldı.'
            : 'Hesap silme işlemi tamamlanamadı. Oturumunuz açık kaldı; '
                  'lütfen tekrar deneyin.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message =
            'Hesap silme işlemi güvenli şekilde tamamlanamadı. '
            'Oturumunuz açık kaldı; lütfen tekrar deneyin.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;

    return Scaffold(
      appBar: AppBar(title: const Text('YoldaAl Hesap Silme')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Hesabınızı ve ilişkili kişisel verilerinizi kalıcı olarak '
                    'silmek için önce YoldaAl hesabınızla kimliğinizi doğrulayın.',
                  ),
                  const SizedBox(height: 16),
                  if (user == null) ...[
                    const Text(
                      'Telefonla kayıt olduysanız telefon numaranızla giriş '
                      'yapmanız önerilir. Google seçeneğini yalnız bu YoldaAl '
                      'hesabında daha önce Google kullandıysanız veya bağladıysanız '
                      'kullanın.',
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      key: const ValueKey(
                        'account-deletion-web-google-sign-in',
                      ),
                      onPressed: _busy ? null : _googleSignIn,
                      child: const Text('Google ile doğrula'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('account-deletion-web-phone'),
                      controller: _phoneController,
                      enabled: !_busy,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Telefon numarası',
                        hintText: '+905551234567',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const ValueKey(
                        'account-deletion-web-send-phone-code',
                      ),
                      onPressed: _busy ? null : _startPhoneSignIn,
                      child: const Text('SMS kodu gönder'),
                    ),
                    if (_phoneCodeSent) ...[
                      const SizedBox(height: 16),
                      TextField(
                        key: const ValueKey('account-deletion-web-phone-code'),
                        controller: _codeController,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'SMS doğrulama kodu',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        key: const ValueKey(
                          'account-deletion-web-confirm-phone-code',
                        ),
                        onPressed: _busy ? null : _confirmPhoneCode,
                        child: const Text('Telefonu doğrula'),
                      ),
                    ],
                  ] else ...[
                    Text(
                      'Doğrulanan hesap: ${user.identityLabel}',
                      key: const ValueKey(
                        'account-deletion-web-authenticated-identity',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Silme işlemi yalnız bu tarayıcı oturumundaki Firebase '
                      'kullanıcı kimliği için çalışır. Başka bir kullanıcı kimliği '
                      'veya sürücü kimliği gönderilmez.',
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      key: const ValueKey(
                        'account-deletion-web-identity-confirmation',
                      ),
                      contentPadding: EdgeInsets.zero,
                      value: _identityConfirmed,
                      onChanged: _busy
                          ? null
                          : (value) {
                              setState(() {
                                _identityConfirmed = value ?? false;
                              });
                            },
                      title: const Text(
                        'Bu oturumun silmek istediğim YoldaAl hesabına ait '
                        'olduğunu doğruluyorum.',
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      key: const ValueKey('account-deletion-web-delete'),
                      onPressed:
                          _busy || _deletionDialogOpen || !_identityConfirmed
                          ? null
                          : _confirmAndDelete,
                      child: const Text('Hesabımı kalıcı olarak sil'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      key: const ValueKey('account-deletion-web-sign-out'),
                      onPressed: _busy ? null : _manualSignOut,
                      child: const Text('Farklı hesapla giriş yap'),
                    ),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _message!,
                      key: const ValueKey('account-deletion-web-message'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Silme isteği sunucu tarafından doğrulanır. Aktif yolculuk '
                    'gibi güvenlik koşulları silme işlemini engelleyebilir.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
