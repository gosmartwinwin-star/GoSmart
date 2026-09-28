import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../services/account_deletion_execution_service.dart';
import '../../services/account_deletion_request_service.dart';
import '../ride/ride_history_screen.dart';

typedef SignOutCallback = Future<void> Function();
typedef AccountDeletionRequestCallback = Future<void> Function();
typedef AccountDeletionExecutionCallback =
    Future<AccountDeletionExecutionResult> Function();

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.phoneNumber,
    this.signOut,
    this.requestAccountDeletion,
    this.executeAccountDeletion,
    this.historyScreenBuilder,
  });

  final String? phoneNumber;
  final SignOutCallback? signOut;
  final AccountDeletionRequestCallback? requestAccountDeletion;
  final AccountDeletionExecutionCallback? executeAccountDeletion;
  final WidgetBuilder? historyScreenBuilder;

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
  bool _requestingDeletion = false;
  String? _errorMessage;

  bool get _operationInFlight => _signingOut || _requestingDeletion;

  Future<void> _confirmSignOut() async {
    if (_operationInFlight) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text(
          'Oturumunuzu kapatmak istediğinizden emin misiniz?',
        ),
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
      final signOut =
          widget.signOut ??
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

  Future<void> _confirmAccountDeletion() async {
    if (_operationInFlight) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hesabı Sil'),
        content: const Text(
          'Hesabınızı kalıcı olarak silmek istediğinizden emin misiniz? '
          'Silinebilen hesap verileriniz güvenli silme sürecinde kaldırılır. '
          'Aktif bir yolculuğunuz varsa işlem tamamlanamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            key: const ValueKey('profile-delete-account-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hesabımı Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _requestingDeletion = true;
      _errorMessage = null;
    });

    try {
      final requestDeletion =
          widget.requestAccountDeletion ??
          () => AccountDeletionRequestService().requestDeletion();
      final executeDeletion =
          widget.executeAccountDeletion ??
          () => AccountDeletionExecutionService().execute();

      await requestDeletion();
      final result = await executeDeletion();

      if (!mounted) return;

      if (result.status == AccountDeletionExecutionStatus.processing) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Silme İşlemi Devam Ediyor'),
            content: const Text(
              'Hesap silme işleminiz devam ediyor. '
              'İşlem tamamlanmadan oturumunuz kapatılmayacaktır. '
              'Daha sonra yeniden deneyebilirsiniz.',
            ),
            actions: [
              FilledButton(
                key: const ValueKey('account-deletion-processing-close'),
                onPressed: () => Navigator.pop(context),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Hesap Silindi'),
          content: const Text(
            'Hesabınız ve silinebilir hesap verileriniz için '
            'silme işlemi tamamlandı.',
          ),
          actions: [
            FilledButton(
              key: const ValueKey('account-deletion-completed-close'),
              onPressed: () => Navigator.pop(context),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );

      final signOut =
          widget.signOut ??
          () => FirebaseAuth.instanceFor(app: Firebase.app()).signOut();
      await signOut();

      if (mounted) {
        await Navigator.of(context).maybePop();
      }
    } on AccountDeletionExecutionException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.reason == 'active_ride_blocks_account_deletion'
            ? 'Aktif yolculuğunuz tamamlanmadan hesabınızı silemezsiniz.'
            : 'Hesap silme işlemi tamamlanamadı. Lütfen tekrar deneyin.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Hesap silme işlemi başlatılamadı. '
            'Bağlantınızı kontrol edip tekrar deneyin.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _requestingDeletion = false;
        });
      }
    }
  }

  Future<void> _openHistory() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder:
            widget.historyScreenBuilder ?? (_) => const RideHistoryScreen(),
      ),
    );
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
              const SizedBox(height: 24),
              Card(
                child: ListTile(
                  key: const ValueKey('profile-ride-history'),
                  leading: const Icon(Icons.history_rounded),
                  title: const Text('Yolculuk geçmişi'),
                  subtitle: const Text(
                    'Yolcu ve sürücü yolculuklarınızı görüntüleyin.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _operationInFlight ? null : _openHistory,
                ),
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  key: const ValueKey('profile-delete-account'),
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Hesabı Sil'),
                  subtitle: Text(
                    _requestingDeletion
                        ? 'Hesap silme işlemi yürütülüyor...'
                        : 'Hesabınızı kalıcı olarak silin.',
                  ),
                  enabled: !_operationInFlight,
                  onTap: _operationInFlight ? null : _confirmAccountDeletion,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _operationInFlight ? null : _confirmSignOut,
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
