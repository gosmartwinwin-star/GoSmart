import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../controllers/driver_center_controller.dart';
import '../../controllers/driver_ride_controller.dart';
import '../../domain/ride/canonical_ride.dart';
import '../../infrastructure/firestore/repositories/firestore_ride_repository.dart';
import '../../services/ride_lifecycle_service.dart';
import '../../widgets/ride/canonical_ride_card.dart';
import '../../core/branding/gosmart_slogans.dart';
import '../../domain/return_route/geo_coordinate.dart';
import '../../infrastructure/firestore/repositories/firestore_driver_access_pass_repository.dart';
import '../../infrastructure/firestore/repositories/firestore_driver_profile_repository.dart';
import '../../models/address_model.dart';
import '../../services/publish_return_route_service.dart';
import '../../domain/driver_application/driver_application_review.dart';
import '../../services/driver_application_review_service.dart';
import 'driver_application_screen.dart';
import 'driver_application_document_resubmission_screen.dart';
import '../../widgets/driver/active_return_route_card.dart';
import '../../widgets/driver/return_route_map_preview.dart';
import '../search/search_address_screen.dart';

class DriverCenterScreen extends StatefulWidget {
  final DriverCenterController? controller;
  final Widget Function()? applicationScreenBuilder;
  final Widget Function(DriverApplicationReview review)?
  resubmissionScreenBuilder;
  final DriverRideController? rideController;

  const DriverCenterScreen({
    super.key,
    this.controller,
    this.applicationScreenBuilder,
    this.resubmissionScreenBuilder,
    this.rideController,
  });

  @override
  State<DriverCenterScreen> createState() => _DriverCenterScreenState();
}

class _DriverCenterScreenState extends State<DriverCenterScreen> {
  late final DriverCenterController controller;
  late final bool _ownsController;
  DriverRideController? rideController;
  late final bool _ownsRideController;
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    controller =
        widget.controller ??
        DriverCenterController(
          auth: _FirebaseDriverCenterAuth(),
          profiles: FirestoreDriverProfileRepository(),
          passes: FirestoreDriverAccessPassRepository(),
          publisher: PublishReturnRouteService(),
          location: _GeolocatorDriverLocation(),
          applications: DriverApplicationReviewService(),
        );
    controller.addListener(_refresh);
    _ownsRideController = widget.rideController == null && widget.controller == null;
    rideController = widget.rideController ?? (widget.controller == null ? DriverRideController(gateway: RideLifecycleService(), repository: FirestoreRideRepository(), authenticatedUserId: () => FirebaseAuth.instance.currentUser?.uid) : null);
    rideController?.addListener(_refresh);
    controller.load();
    rideController?.recover();
    if (_ownsRideController) { _authSubscription = FirebaseAuth.instance.userChanges().skip(1).listen((user) => rideController?.authChanged(user?.uid)); }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    rideController?.removeListener(_refresh);
    _authSubscription?.cancel();
    if (_ownsRideController) rideController?.dispose();
    if (_ownsController) controller.dispose();
    super.dispose();
  }

  Future<void> _selectDestination() async {
    final result = await Navigator.push<AddressModel>(
      context,
      MaterialPageRoute(builder: (_) => const SearchAddressScreen()),
    );
    if (result == null) return;
    controller.selectDestination(
      GeoCoordinate(latitude: result.latitude, longitude: result.longitude),
      result.title,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sürücü Merkezi')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Icon(Icons.local_taxi_rounded, size: 48),
            const SizedBox(height: 8),
            const Text(
              'GoSmart',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const Text(
              GoSmartSlogans.driver,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            _content(),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (rideController?.ride != null) return _activeRide();
    switch (controller.status) {
      case DriverCenterStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case DriverCenterStatus.error:
        return _StatusCard(
          title: 'Bilgiler yüklenemedi',
          description: 'Sürücü bilgileriniz şu anda alınamadı.',
          action: TextButton(
            onPressed: controller.load,
            child: const Text('Tekrar Dene'),
          ),
        );
      case DriverCenterStatus.restricted:
        return _restricted();
      case DriverCenterStatus.ready:
        return _ready();
    }
  }

  Widget _restricted() {
    if (controller.rejectionReason == 'driver_profile_required') {
      return _applicationStatus();
    }
    final values = switch (controller.rejectionReason) {
      'authentication_required' => (
        'Oturum gerekli',
        'Sürücü özelliklerini kullanmak için giriş yapmalısınız.',
        null,
      ),
      'driver_profile_required' => (
        'Sürücü profili gerekli',
        'Dönüş rotası yayımlamak için onaylı bir sürücü profiliniz olmalıdır.',
        'Sürücü başvurusu yakında',
      ),
      'driver_approval_required' => (
        'Profiliniz inceleniyor',
        'Sürücü başvurunuz onaylandıktan sonra dönüş rotası yayımlayabilirsiniz.',
        null,
      ),
      'driver_suspended' => ('Sürücü erişimi askıya alındı', '', null),
      'driver_rejected' => ('Sürücü başvurusu onaylanmadı', '', null),
      'driver_deactivated' => ('Sürücü profili devre dışı', '', null),
      'subscription_required' => (
        'Aktif kontör paketi gerekli',
        'Dönüş rotası yayımlamak için aktif bir GoSmart kontör paketiniz olmalıdır.',
        'Kontör paketleri yakında',
      ),
      _ => ('Bilgiler yüklenemedi', 'Lütfen tekrar deneyin.', null),
    };
    return _StatusCard(
      title: values.$1,
      description: values.$2,
      footer: values.$3,
    );
  }

  Widget _applicationStatus() {
    if (controller.applicationLoadFailed) {
      return _StatusCard(
        title: 'Başvuru bilgileri yüklenemedi',
        description: 'Lütfen tekrar deneyin.',
        action: TextButton(
          onPressed: controller.load,
          child: const Text('Tekrar Dene'),
        ),
      );
    }
    final application = controller.application;
    if (application == null) {
      return _StatusCard(
        title: 'Sürücü profili gerekli',
        description:
            'Dönüş rotası yayımlamak için onaylı bir sürücü profiliniz olmalıdır.',
        action: FilledButton(
          onPressed: _openApplication,
          child: const Text('Sürücü Başvurusu Yap'),
        ),
      );
    }
    return switch (application.state) {
      DriverApplicationReviewState.pendingReview => const _StatusCard(
        title: 'Başvurunuz inceleniyor',
        description: 'Sürücü başvurunuz değerlendirme aşamasında.',
      ),
      DriverApplicationReviewState.approved => _StatusCard(
        title: 'Başvurunuz onaylandı',
        description:
            'Sürücü profiliniz hazırlanıyor. Kısa süre sonra tekrar kontrol edin.',
        action: TextButton(
          onPressed: controller.load,
          child: const Text('Tekrar Kontrol Et'),
        ),
      ),
      DriverApplicationReviewState.awaitingDocumentResubmission => _StatusCard(
        title: 'Belge Yenileme Gerekli',
        description:
            'Başvurunuzdaki bir veya daha fazla belgenin yeniden '
            'yüklenmesi gerekiyor.',
        action: FilledButton(
          onPressed: () => _openResubmission(application),
          child: const Text('Belgeleri Yenile'),
        ),
      ),
      DriverApplicationReviewState.rejected => _StatusCard(
        title: 'Başvurunuz reddedildi',
        description:
            application.finalRejectionReason?.label ??
            'Başvurunuz bu aşamada yeniden gönderilemez.',
      ),
      DriverApplicationReviewState.withdrawn => const _StatusCard(
        title: 'Başvurunuz geri çekildi',
        description: 'Başvurunuz geri çekilmiş durumda.',
      ),
    };
  }

  Future<void> _openApplication() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            widget.applicationScreenBuilder?.call() ??
            const DriverApplicationScreen(),
      ),
    );
    if (result == true) await controller.load();
  }

  Future<void> _openResubmission(DriverApplicationReview review) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            widget.resubmissionScreenBuilder?.call(review) ??
            DriverApplicationDocumentResubmissionScreen(initialReview: review),
      ),
    );
    if (result == true) await controller.load();
  }

  Widget _ready() {
    if (rideController?.ride != null) return _activeRide();
    final published = controller.publishedRoute;
    if (published != null) {
      return Column(
        children: [
          ReturnRouteMapPreview(published: published),
          const SizedBox(height: 12),
          ActiveReturnRouteCard(
            published: published,
            destinationLabel: controller.destinationLabel ?? 'Dönüş hedefi',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Dönüş Rotanı Oluştur',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Boş döneceğiniz güzergâhı paylaşın, aynı yöndeki yolcularla eşleşin.',
        ),
        const SizedBox(height: 20),
        ListTile(
          leading: const Icon(Icons.my_location),
          title: const Text('Başlangıç: Mevcut konumunuz'),
          subtitle: controller.locationLoading
              ? const LinearProgressIndicator()
              : controller.origin == null
              ? Text(controller.errorMessage ?? 'Konum bekleniyor')
              : const Text('Konum hazır'),
          trailing: controller.origin == null && !controller.locationLoading
              ? TextButton(
                  onPressed: controller.loadLocation,
                  child: const Text('Tekrar Dene'),
                )
              : null,
        ),
        OutlinedButton.icon(
          onPressed: _selectDestination,
          icon: const Icon(Icons.flag_outlined),
          label: Text(controller.destinationLabel ?? 'Dönüş hedefi seç'),
        ),
        const SizedBox(height: 16),
        const Text('Geçerlilik süresi'),
        Wrap(
          spacing: 8,
          children:
              const {
                    900: '15 dk',
                    1800: '30 dk',
                    3600: '1 saat',
                    7200: '2 saat',
                    14400: '4 saat',
                  }.entries
                  .map(
                    (entry) => ChoiceChip(
                      label: Text(entry.value),
                      selected: controller.validForSeconds == entry.key,
                      onSelected: (_) => controller.selectValidity(entry.key),
                    ),
                  )
                  .toList(),
        ),
        if (controller.errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            controller.errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: controller.canPublish ? controller.publish : null,
          child: controller.publishing
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Dönüş Rotasını Yayınla'),
        ),
      ],
    );
  }

  Widget _activeRide() {
    final lifecycle = rideController!;
    final activeRide = lifecycle.ride!;
    final primary = switch (activeRide.status) {
      RideStatus.driverEnRoute => () => lifecycle.act(DriverRideAction.arrive),
      RideStatus.driverArrived => () => lifecycle.act(DriverRideAction.start),
      RideStatus.inProgress => () => lifecycle.act(DriverRideAction.complete),
      _ => null,
    };
    final canCancel = activeRide.status == RideStatus.driverEnRoute ||
        activeRide.status == RideStatus.driverArrived;
    return CanonicalRideCard(
      ride: activeRide,
      driver: true,
      loading: lifecycle.mutating,
      onPrimary: primary,
      onCancel: canCancel
          ? () => lifecycle.act(DriverRideAction.cancel)
          : null,
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String title;
  final String description;
  final String? footer;
  final Widget? action;
  const _StatusCard({
    required this.title,
    required this.description,
    this.footer,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center),
          ],
          if (footer != null) ...[
            const SizedBox(height: 12),
            Text(footer!, style: const TextStyle(color: Colors.grey)),
          ],
          ?action,
        ],
      ),
    ),
  );
}

class _FirebaseDriverCenterAuth implements DriverCenterAuthGateway {
  @override
  String? get authenticatedUserId => FirebaseAuth.instance.currentUser?.uid;
}

class _GeolocatorDriverLocation implements DriverLocationGateway {
  @override
  Future<GeoCoordinate> currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Konum servisi kapalı.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Konum izni bulunmuyor.');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
    );
    return GeoCoordinate(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}
