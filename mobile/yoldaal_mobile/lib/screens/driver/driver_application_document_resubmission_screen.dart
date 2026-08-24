import 'package:flutter/material.dart';

import '../../controllers/driver_application_document_resubmission_controller.dart';
import '../../domain/driver_application/driver_application_document_type.dart';
import '../../domain/driver_application/driver_application_review.dart';
import '../../infrastructure/file_picker/flutter_driver_application_file_picker.dart';
import '../../services/driver_application_document_upload_service.dart';
import '../../services/driver_application_review_service.dart';

class DriverApplicationDocumentResubmissionScreen extends StatefulWidget {
  const DriverApplicationDocumentResubmissionScreen({
    super.key,
    required this.initialReview,
    this.controller,
  });

  final DriverApplicationReview initialReview;
  final DriverApplicationDocumentResubmissionController? controller;

  @override
  State<DriverApplicationDocumentResubmissionScreen> createState() =>
      _DriverApplicationDocumentResubmissionScreenState();
}

class _DriverApplicationDocumentResubmissionScreenState
    extends State<DriverApplicationDocumentResubmissionScreen> {
  late final DriverApplicationDocumentResubmissionController controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    if (widget.controller case final injected?) {
      controller = injected;
    } else {
      final service = DriverApplicationReviewService();
      controller = DriverApplicationDocumentResubmissionController(
        initialReview: widget.initialReview,
        reviews: service,
        picker: FlutterDriverApplicationFilePicker(),
        uploader: DriverApplicationDocumentUploadService(),
        resubmitter: service,
      );
    }
    controller.addListener(_refresh);
    controller.refresh();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    if (_ownsController) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Belge Yenileme')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Başvurunuzun yeniden incelenebilmesi için aşağıdaki belgeleri '
            'güncelleyin.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          if (controller.loading) const LinearProgressIndicator(),
          for (final document in controller.review.documents) ...[
            _DocumentCard(
              document: document,
              controller: controller,
              onSelect: () => _select(document.type),
            ),
            const SizedBox(height: 10),
          ],
          if (controller.errorMessage != null) ...[
            Text(
              controller.errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: controller.canSubmit ? _submit : null,
            child: controller.submitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Yeniden Gönder'),
          ),
        ],
      ),
    ),
  );

  Future<void> _select(DriverApplicationDocumentType type) async {
    if (!controller.isEditable(type)) return;
    final source =
        await showModalBottomSheet<DriverDocumentResubmissionPickSource>(
          context: context,
          builder: (context) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Kameradan Çek'),
                  onTap: () => Navigator.pop(
                    context,
                    DriverDocumentResubmissionPickSource.camera,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_outlined),
                  title: const Text('Galeriden Seç'),
                  onTap: () => Navigator.pop(
                    context,
                    DriverDocumentResubmissionPickSource.gallery,
                  ),
                ),
                if (type.allowedContentTypes.contains('application/pdf'))
                  ListTile(
                    leading: const Icon(Icons.picture_as_pdf_outlined),
                    title: const Text('PDF Seç'),
                    onTap: () => Navigator.pop(
                      context,
                      DriverDocumentResubmissionPickSource.pdf,
                    ),
                  ),
              ],
            ),
          ),
        );
    if (source != null) await controller.pickAndUpload(type, source);
  }

  Future<void> _submit() async {
    if (await controller.submit() && mounted) Navigator.pop(context, true);
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.document,
    required this.controller,
    required this.onSelect,
  });

  final DriverApplicationReviewDocument document;
  final DriverApplicationDocumentResubmissionController controller;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final uploadState = controller.uploadStates[document.type];
    final editable = controller.isEditable(document.type);
    final selected = controller.selectedFiles[document.type];
    final statusText = switch (document.status) {
      DriverApplicationPublicDocumentStatus.approved => 'Onaylandı',
      DriverApplicationPublicDocumentStatus.pendingReview =>
        'Yeni belge gönderimi bekleniyor',
      DriverApplicationPublicDocumentStatus.reuploadRequired =>
        'Yeniden yükleme gerekli',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              document.type.displayName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(statusText),
            if (document.reuploadReason != null) ...[
              const SizedBox(height: 4),
              Text(document.reuploadReason!.label),
            ],
            if (selected != null) ...[
              const SizedBox(height: 6),
              Text(
                '${selected.contentType} • '
                '${(selected.sizeBytes / 1024).ceil()} KB',
              ),
            ],
            if (uploadState ==
                DriverDocumentResubmissionUploadState.uploading) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(semanticsLabel: 'Belge yükleniyor'),
            ],
            if (controller.uploadErrors[document.type] case final error?) ...[
              const SizedBox(height: 6),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (editable) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: controller.submitting ? null : onSelect,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(
                  uploadState == DriverDocumentResubmissionUploadState.uploaded
                      ? 'Belgeyi Değiştir'
                      : uploadState ==
                            DriverDocumentResubmissionUploadState.failed
                      ? 'Tekrar Dene'
                      : 'Belge Seç',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
