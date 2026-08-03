import 'package:flutter/material.dart';
import '../application/ports.dart';
import '../controllers/driver_applications_controller.dart';
import '../core/formatting.dart';

final class DriverApplicationDetailsScreen extends StatefulWidget {
  const DriverApplicationDetailsScreen({
    required this.applicationId,
    required this.gateway,
    super.key,
  });
  final String applicationId;
  final DriverApplicationAdminReadGateway gateway;
  @override
  State<DriverApplicationDetailsScreen> createState() =>
      _DriverApplicationDetailsScreenState();
}

class _DriverApplicationDetailsScreenState
    extends State<DriverApplicationDetailsScreen> {
  late final DriverApplicationDetailsController controller;
  @override
  void initState() {
    super.initState();
    controller = DriverApplicationDetailsController(widget.gateway);
    controller.load(widget.applicationId);
  }

  @override
  void dispose() {
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
                  .map(
                    (d) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(d.documentType.label),
                      subtitle: Text(
                        '${d.contentType} • ${formatFileSize(d.sizeBytes)}\n${rejectionReasonLabel(d.rejectionReasonCode)}',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(d.reviewStatus.label),
                          if (d.reviewedAt != null)
                            Text(
                              formatAdminDate(d.reviewedAt!),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        );
      },
    ),
  );

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
