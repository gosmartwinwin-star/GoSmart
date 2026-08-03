import 'dart:async';
import 'package:flutter/material.dart';
import '../application/ports.dart';
import '../controllers/admin_auth_controller.dart';
import '../controllers/driver_application_review_actions_controller.dart';
import '../controllers/driver_applications_controller.dart';
import '../core/formatting.dart';
import '../domain/driver_application.dart';
import '../widgets/document_preview_renderer.dart';

final class DriverApplicationDetailsScreen extends StatefulWidget {
  const DriverApplicationDetailsScreen({
    required this.applicationId,
    required this.gateway,
    required this.reviews,
    required this.refreshList,
    required this.auth,
    super.key,
  });
  final String applicationId;
  final DriverApplicationAdminReadGateway gateway;
  final DriverApplicationAdminReviewGateway reviews;
  final Future<void> Function() refreshList;
  final AdminAuthController auth;
  @override
  State<DriverApplicationDetailsScreen> createState() =>
      _DriverApplicationDetailsScreenState();
}

class _DriverApplicationDetailsScreenState
    extends State<DriverApplicationDetailsScreen> {
  late final DriverApplicationDetailsController controller;
  late final DriverApplicationReviewActionsController actions;

  @override
  void initState() {
    super.initState();
    controller = DriverApplicationDetailsController(widget.gateway);
    actions = DriverApplicationReviewActionsController(
      gateway: widget.reviews,
      refreshDetails: controller.refresh,
      refreshList: widget.refreshList,
      clearDetails: controller.clearSensitiveState,
      handleAuthFailure: widget.auth.signOut,
    );
    controller.load(widget.applicationId);
  }

  @override
  void dispose() {
    actions.clearSensitiveState();
    actions.dispose();
    controller.clearSensitiveState();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Sürücü Başvurusu'),
      leading: const Tooltip(
        message: 'Başvuru Listesine Dön',
        child: BackButton(),
      ),
    ),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.isLoading) {
          return const Center(
            child: CircularProgressIndicator(
              semanticsLabel: 'Başvuru ayrıntısı yükleniyor',
            ),
          );
        }
        if (controller.errorMessage != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(controller.errorMessage!),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: controller.refresh,
                  child: const Text('Tekrar Dene'),
                ),
              ],
            ),
          );
        }
        final details = controller.details;
        if (details == null) return const SizedBox.shrink();
        final a = details.application;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _section(context, 'Başvuru Özeti', [
              _row('Durum', a.status.label),
              _row('Başvuru tarihi', formatAdminDate(a.submittedAt)),
              _row('Güncellenme tarihi', formatAdminDate(a.updatedAt)),
              if (a.reviewedAt != null)
                _row('İnceleme tarihi', formatAdminDate(a.reviewedAt!)),
              _row('Başvuru sürümü', '${a.submissionVersion}'),
              if (a.rejectionReasonCode != null)
                _row(
                  'İnceleme açıklaması',
                  rejectionReasonLabel(a.rejectionReasonCode),
                ),
            ]),
            _section(context, 'Kişisel Bilgiler', [
              _row('Ad Soyad', a.fullName),
              _row('Doğrulanmış telefon', a.verifiedPhoneNumber),
              _row('E-posta', a.email ?? '—'),
            ]),
            _section(context, 'Çalışma Bilgileri', [
              _row('Çalışma şekli', a.workType.label),
              _row('Taksi durağı', a.driverTaxiStandName ?? '—'),
              _row('Durak adresi', a.driverTaxiStandAddress ?? '—'),
            ]),
            _section(context, 'Araç Bilgileri', [
              _row('Plaka', a.vehiclePlate),
              _row('Marka', a.vehicleBrand),
              _row('Model', a.vehicleModel),
              _row('Model yılı', '${a.vehicleModelYear}'),
              _row('Ruhsat sahibi', a.registrationOwnerType.label),
              _row(
                'Araç kullanım yetkisi',
                _yesNo(a.hasVehicleUseAuthorization),
              ),
              _row('Aracın bağlı olduğu durak', a.vehicleTaxiStandName ?? '—'),
            ]),
            _section(context, 'Beyanlar', [
              _row('Bilgi doğruluğu', _yesNo(a.informationAccuracyAccepted)),
              _row(
                'Belge geçerlilik bildirimi',
                _yesNo(a.documentValidityNotificationAccepted),
              ),
              _row(
                'Belge işleme bildirimi',
                _yesNo(a.documentProcessingNoticeAccepted),
              ),
              _row('KVKK bildirimi', _yesNo(a.kvkkNoticeAccepted)),
              _row('Koşullar', _yesNo(a.termsAccepted)),
              _row('Pazarlama izni', _yesNo(a.marketingConsent)),
            ]),
            _section(
              context,
              'Belgeler',
              details.documents
                  .map((document) => _documentRow(details, document))
                  .toList(),
            ),
            _decisionCard(details),
          ],
        );
      },
    ),
  );

  Widget _documentRow(
    DriverApplicationReviewDetails details,
    DriverApplicationReviewDocument document,
  ) {
    final canMutate =
        details.application.status ==
            DriverApplicationReviewStatus.pendingReview &&
        document.reviewStatus == DocumentReviewStatus.pendingReview;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            document.documentType.label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            '${document.reviewStatus.label} • ${document.contentType} • ${formatFileSize(document.sizeBytes)}',
          ),
          if (document.reviewedAt != null)
            Text(formatAdminDate(document.reviewedAt!)),
          if (document.rejectionReasonCode != null)
            Text(rejectionReasonLabel(document.rejectionReasonCode)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openPreview(details, document),
                icon: const Icon(Icons.visibility_outlined),
                label: Semantics(
                  label: '${document.documentType.label} belgesini görüntüle',
                  child: const Text('Görüntüle'),
                ),
              ),
              FilledButton.tonal(
                onPressed: canMutate
                    ? () => _confirmDocumentApproval(details, document)
                    : null,
                child: Semantics(
                  label: '${document.documentType.label} belgesini onayla',
                  child: const Text('Onayla'),
                ),
              ),
              OutlinedButton(
                onPressed: canMutate
                    ? () => _requestReupload(details, document)
                    : null,
                child: Semantics(
                  label:
                      '${document.documentType.label} belgesi için yeniden yükleme iste',
                  child: const Text('Yeniden Yükleme İste'),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }

  Future<void> _openPreview(
    DriverApplicationReviewDetails details,
    DriverApplicationReviewDocument document,
  ) async {
    unawaited(
      actions.openDocumentPreview(
        applicationId: widget.applicationId,
        reviewContext: details.reviewContext,
        documentType: document.documentType,
      ),
    );
    if (!mounted) {
      return;
    }
    final reopen = await showDialog<bool>(
      context: context,
      builder: (context) => DriverApplicationDocumentPreviewDialog(
        controller: actions,
        documentType: document.documentType,
      ),
    );
    actions.closeDocumentPreview();
    if (reopen == true && mounted) {
      await _openPreview(details, document);
    }
  }

  Future<void> _confirmDocumentApproval(
    DriverApplicationReviewDetails details,
    DriverApplicationReviewDocument document,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Belgeyi Onayla'),
        content: Text(
          '${document.documentType.label}\n\nBu belgenin güncel başvuru sürümü için uygun olduğunu onaylıyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Belgeyi Onayla'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await actions.approveDocument(
      applicationId: widget.applicationId,
      reviewContext: details.reviewContext,
      documentType: document.documentType,
    );
    _showActionResult(ok);
  }

  Future<void> _requestReupload(
    DriverApplicationReviewDetails details,
    DriverApplicationReviewDocument document,
  ) async {
    final reason = await showDialog<DriverDocumentReuploadReason>(
      context: context,
      builder: (_) =>
          RequestDocumentReuploadDialog(documentType: document.documentType),
    );
    if (reason == null) return;
    final ok = await actions.requestDocumentReupload(
      applicationId: widget.applicationId,
      reviewContext: details.reviewContext,
      documentType: document.documentType,
      reason: reason,
    );
    _showActionResult(ok);
  }

  Widget _decisionCard(DriverApplicationReviewDetails details) {
    final approved = details.documents
        .where((d) => d.reviewStatus == DocumentReviewStatus.approved)
        .length;
    final pending =
        details.application.status ==
        DriverApplicationReviewStatus.pendingReview;
    final canApprove =
        pending &&
        approved == DriverDocumentType.values.length &&
        details.documents.length == DriverDocumentType.values.length;
    return _section(context, 'Başvuru Kararı', [
      _row('Güncel durum', details.application.status.label),
      _row('Belge özeti', '$approved / ${details.documents.length} onaylandı'),
      if (!canApprove)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Başvurunun onaylanabilmesi için tüm güncel belgeler onaylanmalıdır.',
          ),
        ),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          FilledButton(
            onPressed: canApprove ? () => _approveApplication(details) : null,
            child: const Text('Başvuruyu Onayla'),
          ),
          OutlinedButton(
            onPressed: pending ? () => _rejectApplication(details) : null,
            child: const Text('Başvuruyu Reddet'),
          ),
        ],
      ),
    ]);
  }

  Future<void> _approveApplication(
    DriverApplicationReviewDetails details,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const ApproveDriverApplicationDialog(),
    );
    if (confirmed != true) return;
    final ok = await actions.approveApplication(
      applicationId: widget.applicationId,
      reviewContext: details.reviewContext,
    );
    _showActionResult(ok);
  }

  Future<void> _rejectApplication(
    DriverApplicationReviewDetails details,
  ) async {
    final reason = await showDialog<DriverApplicationRejectionReason>(
      context: context,
      builder: (_) => const RejectDriverApplicationDialog(),
    );
    if (reason == null) return;
    final ok = await actions.rejectApplication(
      applicationId: widget.applicationId,
      reviewContext: details.reviewContext,
      reason: reason,
    );
    _showActionResult(ok);
  }

  void _showActionResult(bool ok) {
    if (!mounted) {
      return;
    }
    final message = ok ? actions.successMessage : actions.actionErrorMessage;
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _yesNo(bool value) => value ? 'Onaylandı' : 'Onaylanmadı';
  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 190,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const Divider(height: 24),
                ...children,
              ],
            ),
          ),
        ),
      );
}

final class DriverApplicationDocumentPreviewDialog extends StatelessWidget {
  const DriverApplicationDocumentPreviewDialog({
    required this.controller,
    required this.documentType,
    super.key,
  });
  final DriverApplicationReviewActionsController controller;
  final DriverDocumentType documentType;
  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: Text(documentType.label),
        actions: [
          IconButton(
            tooltip: 'Kapat',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (controller.isLoadingPreview) {
            return const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Belge önizlemesi yükleniyor',
              ),
            );
          }
          final preview = controller.activePreview;
          if (preview == null) {
            final expired =
                controller.previewErrorMessage?.contains('süresi doldu') ==
                true;
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    controller.previewErrorMessage ??
                        'Belge şu anda görüntülenemedi.',
                  ),
                  if (expired) ...[
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Belgeyi Yeniden Aç'),
                    ),
                  ],
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  '${preview.contentType} • ${formatFileSize(preview.sizeBytes)}',
                ),
                const Text('Belge erişimi kısa sürelidir.'),
                const SizedBox(height: 12),
                Expanded(
                  child: buildDocumentPreviewRenderer(
                    preview: preview,
                    semanticLabel: '${documentType.label} belge önizlemesi',
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

final class RequestDocumentReuploadDialog extends StatefulWidget {
  const RequestDocumentReuploadDialog({required this.documentType, super.key});
  final DriverDocumentType documentType;
  @override
  State<RequestDocumentReuploadDialog> createState() =>
      _RequestDocumentReuploadDialogState();
}

class _RequestDocumentReuploadDialogState
    extends State<RequestDocumentReuploadDialog> {
  DriverDocumentReuploadReason? reason;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Yeniden Yükleme İste'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.documentType.label),
        const Text(
          'Başvuru sahibi bu belgeyi yeniden yüklemek zorunda kalacaktır.',
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<DriverDocumentReuploadReason>(
          initialValue: reason,
          decoration: const InputDecoration(labelText: 'Neden'),
          items: DriverDocumentReuploadReason.values
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text(value.label)),
              )
              .toList(),
          onChanged: (value) => setState(() => reason = value),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: reason == null ? null : () => Navigator.pop(context, reason),
        child: const Text('Yeniden Yükleme İste'),
      ),
    ],
  );
}

final class ApproveDriverApplicationDialog extends StatefulWidget {
  const ApproveDriverApplicationDialog({super.key});
  @override
  State<ApproveDriverApplicationDialog> createState() =>
      _ApproveDriverApplicationDialogState();
}

class _ApproveDriverApplicationDialogState
    extends State<ApproveDriverApplicationDialog> {
  String confirmation = '';
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Başvuruyu Onayla'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Bu işlem başvuruyu onaylayacak ve backend tarafından sürücü profili oluşturulacaktır. Devam etmek istiyor musunuz?',
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(labelText: 'ONAYLA yazın'),
          onChanged: (value) => setState(() => confirmation = value),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: confirmation == 'ONAYLA'
            ? () => Navigator.pop(context, true)
            : null,
        child: const Text('Başvuruyu Onayla'),
      ),
    ],
  );
}

final class RejectDriverApplicationDialog extends StatefulWidget {
  const RejectDriverApplicationDialog({super.key});
  @override
  State<RejectDriverApplicationDialog> createState() =>
      _RejectDriverApplicationDialogState();
}

class _RejectDriverApplicationDialogState
    extends State<RejectDriverApplicationDialog> {
  DriverApplicationRejectionReason? reason;
  String confirmation = '';
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Başvuruyu Reddet'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Bu işlem başvuruyu reddedecektir.'),
        const SizedBox(height: 12),
        DropdownButtonFormField<DriverApplicationRejectionReason>(
          initialValue: reason,
          decoration: const InputDecoration(labelText: 'Ret nedeni'),
          items: DriverApplicationRejectionReason.values
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text(value.label)),
              )
              .toList(),
          onChanged: (value) => setState(() => reason = value),
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(labelText: 'REDDET yazın'),
          onChanged: (value) => setState(() => confirmation = value),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: reason != null && confirmation == 'REDDET'
            ? () => Navigator.pop(context, reason)
            : null,
        child: const Text('Başvuruyu Reddet'),
      ),
    ],
  );
}
