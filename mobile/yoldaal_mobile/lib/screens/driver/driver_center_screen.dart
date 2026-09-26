import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import '../../widgets/ride/ride_midtrip_route_change_panel.dart';

import '../../application/driver_access/driver_plan_purchase_gateway.dart';
import '../../application/ride/ride_support_gateway.dart';
import '../../application/ride/ride_chat_gateway.dart';
import '../../controllers/driver_center_controller.dart';
import '../../controllers/driver_live_tracking_controller.dart';
import '../../controllers/driver_push_target_lifecycle_controller.dart';
import '../../controllers/ride_midtrip_route_change_controller.dart';
import '../../infrastructure/firestore/repositories/firestore_ride_dropoff_change_proposal_event_repository.dart';
import '../../services/ride_midtrip_route_change_service.dart';
import '../../controllers/driver_plan_purchase_controller.dart';
import '../../controllers/driver_ride_controller.dart';
import '../../controllers/driver_ride_match_offer_controller.dart';
import '../../domain/ride/canonical_ride.dart';
import '../../domain/ride/ride_match_offer.dart';
import '../../domain/subscription/driver_access_mode.dart';
import '../../infrastructure/firestore/repositories/firestore_ride_repository.dart';
import '../../services/ride_lifecycle_service.dart';
import '../../services/ride_match_offer_service.dart';
import '../../widgets/location/location_access_banner.dart';
import '../../widgets/ride/canonical_ride_card.dart';
import '../../widgets/ride/ride_active_support_panel.dart';
import '../../widgets/ride/ride_chat_panel.dart';
import '../../core/branding/yoldaal_slogans.dart';
import '../../core/ride/secure_request_id.dart';
import '../../domain/return_route/geo_coordinate.dart';
import '../../infrastructure/firestore/repositories/firestore_driver_access_mode_repository.dart';
import '../../infrastructure/firestore/repositories/firestore_driver_access_pass_repository.dart';
import '../../infrastructure/firestore/repositories/firestore_driver_profile_repository.dart';
import '../../models/address_model.dart';
import '../../services/location_access_service.dart';
import '../../services/active_return_route_recovery_service.dart';
import '../../services/publish_return_route_service.dart';
import '../../services/publish_driver_live_location_service.dart';
import '../../services/driver_offer_push_hint_service.dart';
import '../../services/driver_notification_permission_service.dart';
import '../../services/driver_push_target_registration_service.dart';
import '../../domain/driver_application/driver_application_review.dart';
import '../../services/driver_application_review_service.dart';
import '../../services/driver_plan_catalog_service.dart';
import '../../services/driver_plan_purchase_service.dart';
import '../../services/driver_plan_payment_page_launcher_service.dart';
import 'driver_application_screen.dart';
import 'driver_application_document_resubmission_screen.dart';
import '../../widgets/driver/active_return_route_card.dart';
import '../../widgets/driver/driver_plan_purchase_panel.dart';
import '../../widgets/driver/ride_match_offer_panel.dart';
import '../../widgets/driver/return_route_map_preview.dart';
import '../profile/profile_screen.dart';
import '../search/search_address_screen.dart';
import '../../controllers/ride_voice_call_recovery_controller.dart';
import '../../widgets/ride/ride_voice_call_status_panel.dart';

class DriverCenterScreen extends StatefulWidget {
  final DriverCenterController? controller;
  final Widget Function()? applicationScreenBuilder;
  final Widget Function(DriverApplicationReview review)?
  resubmissionScreenBuilder;
  final DriverRideController? rideController;
  final RideMidtripRouteChangeController? midtripRouteChangeController;
  final DriverRideMatchOfferController? rideMatchOfferController;
  final DriverPlanPurchaseController? driverPlanPurchaseController;
  final DriverPushTargetLifecycle? pushTargetLifecycle;
  final DriverOfferPushHintSource? offerPushHintSource;
  final DriverNotificationPermissionGateway? notificationPermissionGateway;
  final RideActiveSupportGateway? activeSupportGateway;
  final String Function()? supportRequestIdGenerator;
  final RideChatGateway? chatGateway;
  final String Function()? chatRequestIdGenerator;

  final RideVoiceCallRecoveryController? voiceCallRecoveryController;

  const DriverCenterScreen({
    super.key,
    this.voiceCallRecoveryController,
    this.controller,
    this.applicationScreenBuilder,
    this.resubmissionScreenBuilder,
    this.rideController,
    this.midtripRouteChangeController,
    this.rideMatchOfferController,
    this.driverPlanPurchaseController,
    this.pushTargetLifecycle,
    this.offerPushHintSource,
    this.notificationPermissionGateway,
    this.activeSupportGateway,
    this.supportRequestIdGenerator,
    this.chatGateway,
    this.chatRequestIdGenerator,
  });

  @override
  State<DriverCenterScreen> createState() => _DriverCenterScreenState();
}

class _DriverCenterScreenState extends State<DriverCenterScreen>
    with WidgetsBindingObserver {
  RideVoiceCallRecoveryController? _voiceCallRecoveryController;
  bool _ownsVoiceCallRecoveryController = false;
  late final DriverCenterController controller;
  late final bool _ownsController;
  DriverRideController? rideController;
  late final bool _ownsRideController;
  DriverRideMatchOfferController? matchOfferController;
  late final bool _ownsMatchOfferController;
  DriverPlanPurchaseController? planPurchaseController;
  bool _ownsPlanPurchaseController = false;
  DriverPushTargetLifecycle? _pushTargetLifecycle;
  bool _ownsPushTargetLifecycle = false;
  DriverOfferPushHintSource? _offerPushHintSource;
  StreamSubscription<int>? _offerPushHintSubscription;
  int _handledOfferPushHintRevision = 0;
  DriverNotificationPermissionGateway? _notificationPermissionGateway;
  DriverNotificationPermissionState? _notificationPermissionState;
  bool _notificationPermissionRequestPending = false;
  String? _matchOfferRouteId;
  bool _driverRideRecoveryRequested = false;
  final Set<String> _entitlementReloadedSettledOperationIds = <String>{};
  StreamSubscription<User?>? _authSubscription;
  DriverLiveTrackingController? _liveTrackingController;
  RideMidtripRouteChangeController? _midtripRouteChangeController;
  bool _ownsMidtripRouteChangeController = false;
  bool _appResumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeVoiceCallRecoveryController();
    _ownsController = widget.controller == null;
    controller =
        widget.controller ??
        DriverCenterController(
          auth: _FirebaseDriverCenterAuth(),
          profiles: FirestoreDriverProfileRepository(),
          passes: FirestoreDriverAccessPassRepository(),
          accessModes: FirestoreDriverAccessModeRepository(),
          publisher: PublishReturnRouteService(),
          livePresence: PublishDriverLiveLocationService(),
          returnRouteRecovery: ActiveReturnRouteRecoveryService(),
          location: LocationAccessService(),
          applications: DriverApplicationReviewService(),
        );
    controller.addListener(_refresh);
    _initializePushTargetLifecycle();
    _ownsRideController =
        widget.rideController == null && widget.controller == null;
    rideController =
        widget.rideController ??
        (widget.controller == null
            ? DriverRideController(
                gateway: RideLifecycleService(),
                repository: FirestoreRideRepository(),
                authenticatedUserId: () =>
                    FirebaseAuth.instance.currentUser?.uid,
              )
            : null);
    rideController?.addListener(_refresh);

    if (_ownsRideController && rideController != null) {
      final trackingLocation = LocationAccessService();

      _liveTrackingController =
          DriverLiveTrackingController(
              rideStatusListenable: rideController!,
              rideStatus: () => rideController?.ride?.status,
              locationStream: trackingLocation.locationStream,
              livePresence: PublishDriverLiveLocationService(),
            )
            ..setAppResumed(_appResumed)
            ..start();
    }

    final injectedMidtripRouteChangeController =
        widget.midtripRouteChangeController;

    if (injectedMidtripRouteChangeController != null) {
      _midtripRouteChangeController = injectedMidtripRouteChangeController;
    } else if (_ownsRideController && rideController != null) {
      _ownsMidtripRouteChangeController = true;
      _midtripRouteChangeController = RideMidtripRouteChangeController(
        rideListenable: rideController!,
        rideId: () => rideController?.ride?.rideId,
        rideStatus: () => rideController?.ride?.status,
        eventGateway: FirestoreRideDropoffChangeProposalEventRepository(),
        routeChangeGateway: RideMidtripRouteChangeService(),
      );
    }

    _midtripRouteChangeController?.start();

    _ownsMatchOfferController =
        widget.rideMatchOfferController == null && widget.controller == null;
    matchOfferController =
        widget.rideMatchOfferController ??
        (widget.controller == null
            ? DriverRideMatchOfferController(gateway: RideMatchOfferService())
            : null);
    matchOfferController?.addListener(_refresh);
    _initializeOfferPushHintSource();
    _initializeDriverNotificationPermission();
    unawaited(_refreshDriverNotificationPermissionStatus());
    planPurchaseController = _resolvePlanPurchaseController();
    controller.load();
    _attachPlanPurchaseController();
    if (_ownsRideController) {
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
        user,
      ) {
        _driverRideRecoveryRequested = false;
        _voiceCallRecoveryController?.authChanged();
        if (user == null) {
          _pushTargetLifecycle?.setEligible(false);
          unawaited(rideController?.authChanged(null));
          return;
        }
        _syncPushTargetLifecycleEligibility();
        _syncDriverRideRecovery();
      });
    } else {
      _syncDriverRideRecovery();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;

    if (_appResumed == resumed) {
      return;
    }

    _appResumed = resumed;
    _liveTrackingController?.setAppResumed(resumed);
    if (resumed) {
      _voiceCallRecoveryController?.appResumed();
    }
    _syncPushTargetLifecycleEligibility();

    if (!resumed) {
      matchOfferController?.stopPolling();
      return;
    }

    unawaited(_refreshDriverNotificationPermissionStatus());

    if (controller.locationIssue != null) {
      unawaited(controller.loadLocation());
    }

    _syncMatchOffers();
  }

  void _initializePushTargetLifecycle() {
    final injected = widget.pushTargetLifecycle;

    if (injected != null) {
      _pushTargetLifecycle = injected;
      _ownsPushTargetLifecycle = false;
      return;
    }

    if (widget.controller != null) {
      _pushTargetLifecycle = null;
      _ownsPushTargetLifecycle = false;
      return;
    }

    final platform = _resolveDriverPushTargetPlatform();

    if (platform == null) {
      _pushTargetLifecycle = null;
      _ownsPushTargetLifecycle = false;
      return;
    }

    _pushTargetLifecycle = DriverPushTargetLifecycleController(
      registration: DriverPushTargetRegistrationService(),
      platform: platform,
    );
    _ownsPushTargetLifecycle = true;
  }

  String? _currentEligibleVoiceRideId() {
    final ride = rideController?.ride;
    if (ride == null) return null;

    final eligible =
        ride.status == RideStatus.driverEnRoute ||
        ride.status == RideStatus.driverArrived ||
        ride.status == RideStatus.inProgress;
    if (!eligible) return null;

    final rideId = ride.rideId.trim();
    return rideId.isEmpty ? null : rideId;
  }

  void _initializeVoiceCallRecoveryController() {
    final injected = widget.voiceCallRecoveryController;

    if (injected != null) {
      _voiceCallRecoveryController = injected;
      _ownsVoiceCallRecoveryController = false;
    } else if (widget.controller == null && widget.rideController == null) {
      _voiceCallRecoveryController = RideVoiceCallRecoveryController(
        currentEligibleRideId: _currentEligibleVoiceRideId,
        isAuthenticated: () => FirebaseAuth.instance.currentUser != null,
      );
      _ownsVoiceCallRecoveryController = true;
    }

    _voiceCallRecoveryController?.start();
  }

  void _disposeVoiceCallRecoveryController() {
    final current = _voiceCallRecoveryController;
    _voiceCallRecoveryController = null;

    if (_ownsVoiceCallRecoveryController) {
      current?.dispose();
    }

    _ownsVoiceCallRecoveryController = false;
  }

  void _initializeOfferPushHintSource() {
    final source =
        widget.offerPushHintSource ??
        (widget.controller == null ? driverOfferPushHintBus : null);

    _offerPushHintSource = source;

    if (source == null) return;

    _offerPushHintSubscription = source.revisions.listen((_) {
      if (!mounted) return;
      _syncMatchOffers();
    });

    if (source.revision > _handledOfferPushHintRevision) {
      scheduleMicrotask(() {
        if (mounted) _syncMatchOffers();
      });
    }
  }

  void _syncPushTargetLifecycleEligibility() {
    _pushTargetLifecycle?.setEligible(
      _appResumed && controller.status == DriverCenterStatus.ready,
    );
  }

  DriverPlanPurchaseController? _resolvePlanPurchaseController() {
    final injected = widget.driverPlanPurchaseController;

    if (injected != null) {
      _ownsPlanPurchaseController = false;
      return injected;
    }

    if (widget.controller != null) {
      _ownsPlanPurchaseController = false;
      return null;
    }

    _ownsPlanPurchaseController = true;
    return DriverPlanPurchaseController(
      gateway: DriverPlanPurchaseService(),
      catalogGateway: DriverPlanCatalogService(),
      paymentPageLauncher: UrlLauncherDriverPlanPaymentPageLauncher(),
    );
  }

  void _attachPlanPurchaseController() {
    planPurchaseController?.addListener(_handlePlanPurchaseChanged);
    _syncSettledEntitlementRefresh();
  }

  void _detachPlanPurchaseController() {
    planPurchaseController?.removeListener(_handlePlanPurchaseChanged);
  }

  void _handlePlanPurchaseChanged() {
    if (!mounted) return;
    _syncSettledEntitlementRefresh();
  }

  void _syncSettledEntitlementRefresh() {
    final paymentStatus = planPurchaseController?.paymentStatus;

    if (paymentStatus == null ||
        paymentStatus.outcome != DriverPlanPaymentOutcome.settled) {
      return;
    }

    final purchaseOperationId = paymentStatus.purchaseOperationId;

    if (!_entitlementReloadedSettledOperationIds.add(purchaseOperationId)) {
      return;
    }

    unawaited(controller.load());
  }

  @override
  void didUpdateWidget(covariant DriverCenterScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      return;
    }

    if (oldWidget.driverPlanPurchaseController ==
        widget.driverPlanPurchaseController) {
      return;
    }

    final previous = planPurchaseController;
    _detachPlanPurchaseController();

    if (_ownsPlanPurchaseController) {
      previous?.dispose();
    }

    planPurchaseController = _resolvePlanPurchaseController();
    _attachPlanPurchaseController();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    _syncPushTargetLifecycleEligibility();
    _syncDriverRideRecovery();
    _syncMatchOffers();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pushTargetLifecycle?.setEligible(false);
    _offerPushHintSubscription?.cancel();
    _offerPushHintSubscription = null;
    _disposeVoiceCallRecoveryController();
    if (_ownsPushTargetLifecycle) {
      _pushTargetLifecycle?.dispose();
    }
    matchOfferController?.stopPolling();
    controller.removeListener(_refresh);
    rideController?.removeListener(_refresh);
    matchOfferController?.removeListener(_refresh);
    _detachPlanPurchaseController();
    _liveTrackingController?.dispose();
    if (_ownsMidtripRouteChangeController) {
      _midtripRouteChangeController?.dispose();
    }
    _authSubscription?.cancel();
    if (_ownsRideController) rideController?.dispose();
    if (_ownsMatchOfferController) matchOfferController?.dispose();
    if (_ownsPlanPurchaseController) planPurchaseController?.dispose();
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

  Future<RideLocation?> _selectMidtripDropoff() async {
    final result = await Navigator.push<AddressModel>(
      context,
      MaterialPageRoute(builder: (_) => const SearchAddressScreen()),
    );

    if (result == null) {
      return null;
    }

    return RideLocation(
      latitude: result.latitude,
      longitude: result.longitude,
      addressLabel: result.title,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sürücü Merkezi'),
        actions: [
          IconButton(
            tooltip: 'Profil',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    phoneNumber: FirebaseAuth.instance.currentUser?.phoneNumber,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Icon(Icons.local_taxi_rounded, size: 48),
            const SizedBox(height: 8),
            const Text(
              'YoldaAl',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const Text(
              YoldaAlSlogans.driver,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            RideVoiceCallStatusPanel(
              controller: _voiceCallRecoveryController,
              viewerRole: RideVoiceCallStatusViewerRole.driver,
            ),
            const SizedBox(height: 24),
            _content(),
            if (controller.status == DriverCenterStatus.ready &&
                _shouldShowDriverNotificationPermissionCard) ...[
              const SizedBox(height: 12),
              _driverNotificationPermissionCard(),
            ],
          ],
        ),
      ),
    );
  }

  void _initializeDriverNotificationPermission() {
    final injected = widget.notificationPermissionGateway;

    if (injected != null) {
      _notificationPermissionGateway = injected;
      return;
    }

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _notificationPermissionGateway = null;
      _notificationPermissionState =
          DriverNotificationPermissionState.unsupported;
      return;
    }

    _notificationPermissionGateway = DriverNotificationPermissionService();
  }

  Future<void> _refreshDriverNotificationPermissionStatus() async {
    final gateway = _notificationPermissionGateway;

    if (gateway == null) return;

    DriverNotificationPermissionState state;

    try {
      state = await gateway.currentStatus();
    } catch (_) {
      state = DriverNotificationPermissionState.failed;
    }

    if (!mounted || !identical(gateway, _notificationPermissionGateway)) {
      return;
    }

    setState(() {
      _notificationPermissionState = state;
    });
  }

  Future<void> _requestDriverNotificationPermission() async {
    final gateway = _notificationPermissionGateway;

    if (gateway == null || _notificationPermissionRequestPending) {
      return;
    }

    setState(() {
      _notificationPermissionRequestPending = true;
    });

    DriverNotificationPermissionState state;

    try {
      state = await gateway.requestFromUserAction();
    } catch (_) {
      state = DriverNotificationPermissionState.failed;
    }

    if (!mounted || !identical(gateway, _notificationPermissionGateway)) {
      return;
    }

    setState(() {
      _notificationPermissionState = state;
      _notificationPermissionRequestPending = false;
    });
  }

  bool get _shouldShowDriverNotificationPermissionCard {
    final state = _notificationPermissionState;

    return state != null &&
        state != DriverNotificationPermissionState.unsupported &&
        state != DriverNotificationPermissionState.authorized;
  }

  Widget _driverNotificationPermissionCard() {
    final state = _notificationPermissionState!;

    final description = switch (state) {
      DriverNotificationPermissionState.deniedPermanently =>
        'Bildirimler cihaz ayarlar\u0131nda kapal\u0131. Teklifleri '
            'ka\u00e7\u0131rmamak i\u00e7in YoldaAl bildirimlerini cihaz '
            'ayarlar\u0131ndan a\u00e7\u0131n.',
      DriverNotificationPermissionState.failed =>
        'Bildirim durumu \u015fu anda kontrol edilemiyor. L\u00fctfen '
            'tekrar deneyin.',
      _ =>
        'Yeni e\u015fle\u015fme tekliflerinden haberdar olmak i\u00e7in '
            'bildirimlere izin verin.',
    };

    final Widget? action = switch (state) {
      DriverNotificationPermissionState.deniedPermanently => null,
      DriverNotificationPermissionState.failed => TextButton(
        key: const ValueKey('driver-notification-permission-action'),
        onPressed: _notificationPermissionRequestPending
            ? null
            : () {
                unawaited(_refreshDriverNotificationPermissionStatus());
              },
        child: const Text('Tekrar Kontrol Et'),
      ),
      _ => TextButton(
        key: const ValueKey('driver-notification-permission-action'),
        onPressed: _notificationPermissionRequestPending
            ? null
            : () {
                unawaited(_requestDriverNotificationPermission());
              },
        child: const Text('Bildirimleri A\u00e7'),
      ),
    };

    return KeyedSubtree(
      key: const ValueKey('driver-notification-permission-card'),
      child: _StatusCard(
        title: 'Teklif bildirimleri',
        description: description,
        action: action,
      ),
    );
  }

  Widget _content() {
    if (rideController?.ride != null) return _activeRide();
    if (rideController?.loading == true) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rideController?.errorMessage case final message?) {
      return _StatusCard(
        title: 'Aktif yolculuk yüklenemedi',
        description: message,
        action: TextButton(
          onPressed: rideController?.recover,
          child: const Text('Tekrar Dene'),
        ),
      );
    }
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
    final purchase = planPurchaseController;

    if (controller.rejectionReason == 'subscription_required' &&
        purchase != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _StatusCard(
            title: 'Aktif kontör paketi gerekli',
            description:
                'Dönüş rotası yayımlamak için aktif bir YoldaAl kontör '
                'paketiniz olmalıdır.',
          ),
          const SizedBox(height: 12),
          DriverPlanPurchasePanel(controller: purchase),
        ],
      );
    }
    if (controller.rejectionReason == 'driver_profile_required') {
      return _applicationStatus();
    }
    final values = switch (controller.rejectionReason) {
      'authentication_required' => (
        'Oturum gerekli',
        'Sürücü özelliklerini kullanmak için giriş yapmalısınız.',
        null,
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
        'Dönüş rotası yayımlamak için aktif bir YoldaAl kontör paketiniz olmalıdır.',
        null,
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

  void _syncDriverRideRecovery() {
    final lifecycle = rideController;
    if (lifecycle == null || _driverRideRecoveryRequested) {
      return;
    }

    final canRecover =
        controller.status == DriverCenterStatus.ready ||
        (controller.status == DriverCenterStatus.restricted &&
            controller.rejectionReason == 'subscription_required');

    if (!canRecover) {
      return;
    }

    _driverRideRecoveryRequested = true;

    if (_ownsRideController) {
      unawaited(lifecycle.authChanged(FirebaseAuth.instance.currentUser?.uid));
      return;
    }

    unawaited(lifecycle.recover());
  }

  void _syncMatchOffers() {
    final matches = matchOfferController;
    final lifecycle = rideController;
    final published = controller.publishedRoute;
    final pushHintRevision = _offerPushHintSource?.revision ?? 0;
    final hasPendingPushHint = pushHintRevision > _handledOfferPushHintRevision;

    if (published == null) {
      _matchOfferRouteId = null;
      matches?.stopPolling();
      return;
    }

    if (matches == null ||
        lifecycle == null ||
        !_appResumed ||
        controller.status != DriverCenterStatus.ready ||
        lifecycle.loading ||
        lifecycle.errorMessage != null ||
        lifecycle.ride != null) {
      matches?.stopPolling();
      return;
    }

    final pollingStarted = matches.startPolling();

    if (matches.busy) {
      return;
    }

    if (hasPendingPushHint) {
      _handledOfferPushHintRevision = pushHintRevision;
      _matchOfferRouteId = published.routeId;
      unawaited(matches.load());
      return;
    }

    if (matches.hasLoaded &&
        _matchOfferRouteId == published.routeId &&
        !pollingStarted) {
      return;
    }

    _matchOfferRouteId = published.routeId;
    unawaited(matches.load());
  }

  Future<void> _acceptMatchOffer(RideMatchOffer offer) async {
    final matches = matchOfferController;
    final lifecycle = rideController;

    if (matches == null || lifecycle == null) {
      return;
    }

    final accepted = await matches.accept(offer);

    if (!accepted) {
      return;
    }

    await lifecycle.recover();
    matches.clearAcceptedRide();
  }

  Widget _ready() {
    final content = _readyContent();
    if (controller.accessMode != DriverAccessMode.launchFree) {
      return content;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StatusCard(
          title: 'Lansman d\u00f6neminde \u00fccretsiz',
          description:
              'YoldaAl, lansman d\u00f6neminde s\u00fcr\u00fcc\u00fcler i\u00e7in \u00fccretsizdir. '
              'S\u00fcr\u00fcc\u00fc eri\u015fimi i\u00e7in abonelik veya paket \u00fccreti al\u0131nmaz.',
        ),
        const SizedBox(height: 12),
        content,
      ],
    );
  }

  Widget _readyContent() {
    if (rideController?.ride != null) return _activeRide();
    final published = controller.publishedRoute;
    if (published != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReturnRouteMapPreview(published: published),
          const SizedBox(height: 12),
          ActiveReturnRouteCard(
            published: published,
            destinationLabel: controller.destinationLabel ?? 'Dönüş hedefi',
          ),
          if (matchOfferController != null && rideController != null) ...[
            const SizedBox(height: 12),
            RideMatchOfferPanel(
              controller: matchOfferController!,
              onAccept: _acceptMatchOffer,
              onRefresh: matchOfferController!.load,
            ),
          ],
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
          title: const Text('Ba\u015flang\u0131\u00e7: Mevcut konumunuz'),
          subtitle: controller.locationLoading
              ? const LinearProgressIndicator()
              : controller.origin != null
              ? const Text('Konum haz\u0131r')
              : controller.locationIssue != null
              ? const Text('Konum eri\u015fimi gerekli')
              : const Text('Konum bekleniyor'),
          trailing:
              controller.origin == null &&
                  !controller.locationLoading &&
                  controller.locationIssue == null
              ? TextButton(
                  onPressed: controller.loadLocation,
                  child: const Text('Tekrar Dene'),
                )
              : null,
        ),
        if (controller.locationIssue case final issue?)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LocationAccessBanner(
              key: const ValueKey('driver-location-access-banner'),
              issue: issue,
              onAction: () {
                unawaited(controller.handleLocationIssueAction());
              },
            ),
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
    final canCancel =
        activeRide.status == RideStatus.driverEnRoute ||
        activeRide.status == RideStatus.driverArrived;
    final canUseSupport =
        activeRide.status == RideStatus.driverEnRoute ||
        activeRide.status == RideStatus.driverArrived ||
        activeRide.status == RideStatus.inProgress;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CanonicalRideCard(
          ride: activeRide,
          driver: true,
          loading: lifecycle.mutating,
          onPrimary: primary,
          onCancel: canCancel
              ? () => lifecycle.act(DriverRideAction.cancel)
              : null,
        ),
        if (activeRide.status == RideStatus.driverEnRoute ||
            activeRide.status == RideStatus.driverArrived ||
            activeRide.status == RideStatus.inProgress ||
            activeRide.status.isTerminal) ...[
          const SizedBox(height: 8),
          RideChatPanel(
            key: ValueKey('driver-ride-chat-${activeRide.rideId}'),
            rideId: activeRide.rideId,
            status: activeRide.status,
            viewerRole: RideChatSenderRole.driver,
            gateway: widget.chatGateway,
            requestIdGenerator:
                widget.chatRequestIdGenerator ?? secureRideRequestId,
          ),
        ],
        if (activeRide.status == RideStatus.inProgress &&
            _midtripRouteChangeController != null) ...[
          const SizedBox(height: 8),
          RideMidtripRouteChangePanel(
            key: ValueKey('driver-midtrip-route-change-${activeRide.rideId}'),
            rideId: activeRide.rideId,
            controller: _midtripRouteChangeController!,
            selectDropoff: _selectMidtripDropoff,
          ),
        ],
        if (canUseSupport) ...[
          const SizedBox(height: 8),
          RideActiveSupportPanel(
            key: ValueKey('driver-active-support-${activeRide.rideId}'),
            rideId: activeRide.rideId,
            gateway: widget.activeSupportGateway,
            requestIdGenerator:
                widget.supportRequestIdGenerator ?? secureRideRequestId,
          ),
        ],
      ],
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

DriverPushTargetPlatform? _resolveDriverPushTargetPlatform() {
  if (kIsWeb) {
    return null;
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.android => DriverPushTargetPlatform.android,
    TargetPlatform.iOS => DriverPushTargetPlatform.ios,
    _ => null,
  };
}

class _FirebaseDriverCenterAuth implements DriverCenterAuthGateway {
  @override
  String? get authenticatedUserId => FirebaseAuth.instance.currentUser?.uid;
}
