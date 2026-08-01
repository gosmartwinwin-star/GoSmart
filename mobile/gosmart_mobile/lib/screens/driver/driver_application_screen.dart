import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../controllers/driver_application_form_controller.dart';
import '../../core/branding/gosmart_slogans.dart';
import '../../core/legal/driver_application_legal_content.dart';
import '../../domain/driver_application/driver_application_document_type.dart';
import '../../domain/driver_application/driver_work_type.dart';
import '../../domain/driver_application/registration_owner_type.dart';
import '../../infrastructure/file_picker/flutter_driver_application_file_picker.dart';
import '../../infrastructure/vehicle_catalog/asset_vehicle_catalog_repository.dart';
import '../../services/driver_application_document_upload_service.dart';
import '../../services/submit_driver_application_service.dart';
import '../../domain/driver_application/vehicle_catalog.dart';
import '../../widgets/forms/searchable_selection_field.dart';

class DriverApplicationScreen extends StatefulWidget {
  final DriverApplicationFormController? controller;
  final DriverApplicationLegalContent legalContent;
  const DriverApplicationScreen({
    super.key,
    this.controller,
    this.legalContent = const DriverApplicationLegalContent(),
  });

  @override
  State<DriverApplicationScreen> createState() =>
      _DriverApplicationScreenState();
}

class _DriverApplicationScreenState extends State<DriverApplicationScreen> {
  late final DriverApplicationFormController controller;
  late final bool _ownsController;
  final fields = List.generate(9, (_) => TextEditingController());

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    controller =
        widget.controller ??
        DriverApplicationFormController(
          picker: FlutterDriverApplicationFilePicker(),
          uploader: DriverApplicationDocumentUploadService(),
          submitter: SubmitDriverApplicationService(),
          userInfo: FirebaseDriverApplicationUserInfoProvider(),
          vehicleCatalogRepository: AssetVehicleCatalogRepository(),
        );
    controller.addListener(_refresh);
    controller.loadVehicleCatalog();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    if (_ownsController) controller.dispose();
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  void _sync() {
    controller
      ..fullName = fields[0].text
      ..email = fields[1].text
      ..driverTaxiStandName = fields[2].text
      ..driverTaxiStandAddress = fields[3].text
      ..vehiclePlate = fields[4].text
      ..vehicleTaxiStandName = fields[8].text;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sürücü Başvurusu')),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(GoSmartSlogans.driver, textAlign: TextAlign.center),
          ),
          _steps(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: KeyedSubtree(
                  key: ValueKey(controller.currentStep),
                  child: [
                    _personal(),
                    _vehicle(),
                    _documents(),
                    _approval(),
                  ][controller.currentStep],
                ),
              ),
            ),
          ),
          if (controller.errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                controller.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          _navigation(),
        ],
      ),
    ),
  );

  Widget _steps() => Padding(
    padding: const EdgeInsets.all(12),
    child: Row(
      children: ['Kişisel', 'Araç', 'Belgeler', 'Onay']
          .asMap()
          .entries
          .map(
            (entry) => Expanded(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: entry.key <= controller.currentStep
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade300,
                    child: Text(
                      '${entry.key + 1}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    child: Text(
                      entry.value,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    ),
  );

  Widget _field(
    int index,
    String label, {
    TextInputType? keyboard,
    bool readOnly = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: fields[index],
      readOnly: readOnly,
      keyboardType: keyboard,
      textCapitalization: index == 4
          ? TextCapitalization.characters
          : TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) {
        _sync();
        controller.changed();
      },
    ),
  );

  Widget _personal() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _field(0, 'Ad Soyad'),
      TextFormField(
        readOnly: true,
        initialValue: controller.verifiedPhoneNumber ?? '',
        decoration: const InputDecoration(
          labelText: 'Doğrulanmış telefon numarası',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      _field(1, 'E-posta (isteğe bağlı)', keyboard: TextInputType.emailAddress),
      _field(2, 'Çalıştığı taksi durağı (isteğe bağlı)'),
      _field(3, 'Taksi durağı adresi veya konumu (isteğe bağlı)'),
      DropdownButtonFormField<DriverWorkType>(
        initialValue: controller.workType,
        decoration: const InputDecoration(
          labelText: 'Sürücü çalışma şekli',
          border: OutlineInputBorder(),
        ),
        items: DriverWorkType.values
            .map(
              (value) => DropdownMenuItem(
                value: value,
                child: Text(value.displayName),
              ),
            )
            .toList(),
        onChanged: (value) {
          controller.workType = value;
          controller.changed();
        },
      ),
    ],
  );

  Widget _vehicle() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _field(4, 'Araç Plakası'),
      if (controller.isVehicleCatalogLoading)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: LinearProgressIndicator(),
        ),
      if (controller.vehicleCatalogErrorMessage != null) ...[
        Text(controller.vehicleCatalogErrorMessage!),
        TextButton(
          onPressed: controller.selectManualVehicleBrand,
          child: const Text('Marka ve modeli elle gir'),
        ),
      ],
      SearchableSelectionField(
        label: 'Araç Markası',
        hint: 'Marka seçin',
        selectedValue: controller.isManualVehicleBrand
            ? 'Listede yok'
            : controller.selectedVehicleBrand,
        items:
            controller.vehicleCatalog?.brands
                .map((item) => item.name)
                .toList() ??
            const [],
        enabled:
            !controller.isVehicleCatalogLoading &&
            controller.vehicleCatalog != null,
        specialOption: 'Listede yok',
        onSelected: (value) => value == 'Listede yok'
            ? controller.selectManualVehicleBrand()
            : controller.selectVehicleBrand(value),
      ),
      const SizedBox(height: 12),
      if (controller.isManualVehicleBrand)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: fields[5],
            maxLength: 50,
            decoration: const InputDecoration(
              labelText: 'Araç Markası (manuel)',
              border: OutlineInputBorder(),
            ),
            onChanged: controller.updateManualVehicleBrand,
          ),
        ),
      if (!controller.isManualVehicleBrand)
        SearchableSelectionField(
          label: 'Araç Modeli',
          hint: controller.selectedVehicleBrand == null
              ? 'Önce araç markasını seçin.'
              : 'Model seçin',
          selectedValue: controller.isManualVehicleModel
              ? 'Diğer model'
              : controller.selectedVehicleModel,
          items: controller.availableVehicleModels,
          enabled: controller.selectedVehicleBrand != null,
          specialOption: 'Diğer model',
          onSelected: (value) => value == 'Diğer model'
              ? controller.selectManualVehicleModel()
              : controller.selectVehicleModel(value),
        ),
      if (controller.isManualVehicleBrand ||
          controller.isManualVehicleModel) ...[
        const SizedBox(height: 12),
        TextField(
          controller: fields[6],
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Araç Modeli (manuel)',
            border: OutlineInputBorder(),
          ),
          onChanged: controller.updateManualVehicleModel,
        ),
      ],
      const SizedBox(height: 12),
      SearchableSelectionField(
        label: 'Model Yılı',
        hint: 'Model yılı seçin',
        selectedValue: controller.selectedVehicleModelYear?.toString(),
        items: VehicleModelYearOptions.build(
          currentUtcYear: DateTime.now().toUtc().year,
        ).map((year) => year.toString()).toList(),
        onSelected: (value) =>
            controller.selectVehicleModelYear(int.parse(value)),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<RegistrationOwnerType>(
        initialValue: controller.registrationOwnerType,
        decoration: const InputDecoration(
          labelText: 'Ruhsat Sahibi',
          border: OutlineInputBorder(),
        ),
        items: RegistrationOwnerType.values
            .map(
              (value) => DropdownMenuItem(
                value: value,
                child: Text(value.displayName),
              ),
            )
            .toList(),
        onChanged: (value) {
          controller.registrationOwnerType = value;
          if (value == RegistrationOwnerType.applicant) {
            controller.hasVehicleUseAuthorization = false;
          }
          controller.changed();
        },
      ),
      if (controller.registrationOwnerType != null &&
          controller.registrationOwnerType != RegistrationOwnerType.applicant)
        CheckboxListTile(
          value: controller.hasVehicleUseAuthorization,
          title: const Text(
            'Bu aracı ticari taksi hizmetinde kullanmaya yetkiliyim.',
          ),
          onChanged: (value) {
            controller.hasVehicleUseAuthorization = value ?? false;
            controller.changed();
          },
        ),
      const SizedBox(height: 12),
      _field(8, 'Aracın bağlı olduğu taksi durağı (isteğe bağlı)'),
    ],
  );

  Widget _documents() => Column(
    children: DriverApplicationDocumentType.values
        .map(
          (type) => Card(
            child: ListTile(
              title: Text(type.displayName),
              subtitle: Text(_uploadLabel(controller.uploadStates[type]!)),
              trailing: FilledButton.tonal(
                onPressed:
                    controller.uploadStates[type] ==
                        DriverApplicationUploadState.uploading
                    ? null
                    : () => _chooseSource(type),
                child: Text(
                  controller.uploadStates[type] ==
                          DriverApplicationUploadState.uploaded
                      ? 'Değiştir'
                      : 'Belge Seç',
                ),
              ),
            ),
          ),
        )
        .toList(),
  );

  String _uploadLabel(DriverApplicationUploadState state) => switch (state) {
    DriverApplicationUploadState.notSelected => 'Yüklenmedi',
    DriverApplicationUploadState.selecting => 'Seçiliyor',
    DriverApplicationUploadState.uploading => 'Yükleniyor',
    DriverApplicationUploadState.uploaded => 'Yüklendi',
    DriverApplicationUploadState.failed => 'Yüklenemedi',
  };

  Future<void> _chooseSource(DriverApplicationDocumentType type) async {
    final source = await showModalBottomSheet<DriverApplicationPickSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Fotoğraf Çek'),
              onTap: () =>
                  Navigator.pop(context, DriverApplicationPickSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galeriden Seç'),
              onTap: () =>
                  Navigator.pop(context, DriverApplicationPickSource.gallery),
            ),
            if (type.allowedContentTypes.contains('application/pdf'))
              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('PDF Seç'),
                onTap: () =>
                    Navigator.pop(context, DriverApplicationPickSource.pdf),
              ),
          ],
        ),
      ),
    );
    if (source != null) await controller.pickAndUpload(type, source);
  }

  Widget _approval() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Başvuru Özeti', style: Theme.of(context).textTheme.titleLarge),
      Text('Ad Soyad: ${controller.fullName}'),
      Text('Çalışma tipi: ${controller.workType?.displayName ?? '-'}'),
      Text(
        'Araç: ${controller.vehiclePlate} • ${controller.effectiveVehicleBrand ?? controller.vehicleBrand} ${controller.effectiveVehicleModel ?? controller.vehicleModel}',
      ),
      Text(
        'Model yılı: ${controller.selectedVehicleModelYear ?? controller.vehicleModelYear}',
      ),
      Text(
        'Ruhsat sahibi: ${controller.registrationOwnerType?.displayName ?? '-'}',
      ),
      const Text('Yedi zorunlu belge tamamlandı.'),
      const Divider(),
      _check(
        'Bilgilerimin ve belgelerimin doğru ve güncel olduğunu kabul ediyorum.',
        controller.informationAccuracyAccepted,
        (v) => controller.informationAccuracyAccepted = v,
      ),
      _check(
        'Geçerliliğini kaybeden belgeyi GoSmart’a bildireceğimi kabul ediyorum.',
        controller.documentValidityNotificationAccepted,
        (v) => controller.documentValidityNotificationAccepted = v,
      ),
      _check(
        'Belgelerimin uygunluk kontrolü amacıyla işleneceği konusunda bilgilendirildim.',
        controller.documentProcessingNoticeAccepted,
        (v) => controller.documentProcessingNoticeAccepted = v,
      ),
      _check(
        widget.legalContent.kvkkTitle,
        controller.kvkkNoticeAccepted,
        (v) => controller.kvkkNoticeAccepted = v,
      ),
      _check(
        widget.legalContent.termsTitle,
        controller.termsAccepted,
        (v) => controller.termsAccepted = v,
      ),
      _check(
        'Pazarlama iletişimine izin veriyorum (isteğe bağlı)',
        controller.marketingConsent,
        (v) => controller.marketingConsent = v,
      ),
      if (!widget.legalContent.isFinalized)
        Text(
          widget.legalContent.kvkkDraftNotice,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );

  Widget _check(String label, bool value, void Function(bool) assign) =>
      CheckboxListTile(
        value: value,
        title: Text(label),
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (next) {
          assign(next ?? false);
          controller.changed();
        },
      );

  Widget _navigation() => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        if (controller.currentStep > 0)
          Expanded(
            child: OutlinedButton(
              onPressed: controller.previous,
              child: const Text('Geri'),
            ),
          ),
        if (controller.currentStep > 0) const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: _actionEnabled ? _action : null,
            child: controller.isSubmitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    controller.currentStep == 3
                        ? 'Başvuruyu Gönder'
                        : 'Devam Et',
                  ),
          ),
        ),
      ],
    ),
  );

  bool get _actionEnabled {
    _sync();
    if (controller.currentStep < 3) {
      return controller.validateStep(controller.currentStep);
    }
    return controller.canSubmit &&
        (widget.legalContent.isFinalized || kDebugMode);
  }

  Future<void> _action() async {
    _sync();
    if (controller.currentStep < 3) {
      controller.next();
      return;
    }
    if (!widget.legalContent.isFinalized && !kDebugMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Başvuru metinleri henüz kullanıma hazır değil.'),
        ),
      );
      return;
    }
    if (await controller.submit() && mounted) {
      for (final field in fields) {
        field.clear();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Başvurunuz incelemeye gönderildi.')),
      );
      Navigator.pop(context, true);
    }
  }
}
