import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../../widgets/ride/ride_midtrip_route_change_panel.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/ride/secure_request_id.dart';
import '../../application/location/location_access_gateway.dart';
import '../../application/ride/ride_support_gateway.dart';
import '../../application/ride/ride_chat_gateway.dart';
import '../../controllers/passenger_ride_controller.dart';
import '../../controllers/passenger_push_target_lifecycle_controller.dart';
import '../../domain/ride/canonical_ride.dart';
import '../../infrastructure/firestore/repositories/firestore_ride_repository.dart';
import '../../models/address_model.dart';
import '../../models/route_result_model.dart';
import '../../screens/search/search_address_screen.dart';
import '../../screens/driver/driver_center_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../services/location_access_service.dart';
import '../../services/route_marker_service.dart';
import '../../services/route_service.dart';
import '../../services/ride_lifecycle_service.dart';
import '../../services/ride_live_tracking_service.dart';
import '../../controllers/passenger_ride_live_tracking_controller.dart';
import '../../controllers/passenger_nearby_driver_controller.dart';
import '../../services/nearby_passenger_driver_service.dart';
import '../../services/passenger_push_target_registration_service.dart';
import '../../controllers/ride_midtrip_route_change_controller.dart';
import '../../infrastructure/firestore/repositories/firestore_ride_dropoff_change_proposal_event_repository.dart';
import '../../services/ride_midtrip_route_change_service.dart';
import '../../widgets/ride/canonical_ride_card.dart';
import '../../widgets/ride/ride_active_support_panel.dart';
import '../../widgets/ride/ride_chat_panel.dart';
import '../../widgets/cards/route_summary_card.dart';
import '../../widgets/location/location_access_banner.dart';
import '../../widgets/map/yoldaal_map.dart';
import '../../widgets/panels/home_bottom_panel.dart';
import '../../widgets/panels/ride_request_panel.dart';

import '../ride/ride_history_screen.dart';
import '../../controllers/ride_voice_call_recovery_controller.dart';

typedef HomeRouteLoader =
    Future<RouteResultModel> Function({
      required LatLng pickup,
      required LatLng destination,
    });

String? passengerActiveRideArrivalContextText({
  required RideStatus status,
  required bool isUpdating,
  required int? etaSeconds,
}) {
  if (status == RideStatus.driverArrived) {
    return 'Sürücünüz geldi';
  }

  if (status == RideStatus.driverEnRoute) {
    if (isUpdating) {
      return 'Sürücünüz yaklaşıyor • Konum güncelleniyor…';
    }

    if (etaSeconds == null) {
      return 'Sürücünüz yaklaşıyor';
    }

    return 'Sürücünüz yaklaşıyor • Tahmini varış: $etaSeconds sn';
  }

  if (status == RideStatus.inProgress) {
    if (isUpdating || etaSeconds == null) {
      return 'Sürücü konumu güncelleniyor…';
    }

    return 'Tahmini varış: $etaSeconds sn';
  }

  return null;
}

class HomeScreen extends StatefulWidget {
  final RideVoiceCallRecoveryController? voiceCallRecoveryController;

  const HomeScreen({
    super.key,
    this.voiceCallRecoveryController,
    this.rideController,
    this.liveTrackingController,
    this.nearbyDriverController,
    this.midtripRouteChangeController,
    this.routeLoader,
    this.authenticate,
    this.locationAccess,
    this.profileScreenBuilder,
    this.activeSupportGateway,
    this.supportRequestIdGenerator,
    this.chatGateway,
    this.chatRequestIdGenerator,
  });
  final PassengerRideController? rideController;
  final PassengerRideLiveTrackingController? liveTrackingController;
  final PassengerNearbyDriverController? nearbyDriverController;
  final RideMidtripRouteChangeController? midtripRouteChangeController;
  final HomeRouteLoader? routeLoader;
  final Future<bool> Function()? authenticate;
  final LocationAccessGateway? locationAccess;
  final WidgetBuilder? profileScreenBuilder;
  final RideActiveSupportGateway? activeSupportGateway;
  final String Function()? supportRequestIdGenerator;
  final RideChatGateway? chatGateway;
  final String Function()? chatRequestIdGenerator;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  RideVoiceCallRecoveryController? _voiceCallRecoveryController;
  bool _ownsVoiceCallRecoveryController = false;
  late final PassengerRideController rideController;
  late final bool _ownsRideController;
  PassengerRideLiveTrackingController? liveTrackingController;
  bool _ownsLiveTrackingController = false;
  PassengerNearbyDriverController? nearbyDriverController;
  bool _ownsNearbyDriverController = false;
  RideMidtripRouteChangeController? midtripRouteChangeController;
  bool _ownsMidtripRouteChangeController = false;
  StreamSubscription<User?>? _authSubscription;
  PassengerPushTargetLifecycle? _passengerPushTargetLifecycle;
  bool _ownsPassengerPushTargetLifecycle = false;
  GoogleMapController? mapController;

  final RouteMarkerService routeMarkerService = RouteMarkerService();

  late final HomeRouteLoader routeLoader;

  late final LocationAccessGateway locationAccess;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  bool _isRouteLoading = false;

  bool _locationLoading = false;
  LocationAccessIssue? _locationIssue;

  int? _routeDistanceMeters;
  int? _routeDurationSeconds;

  AddressModel? pickupAddress;

  AddressModel? destinationAddress;

  final CameraPosition _initialPosition = const CameraPosition(
    target: LatLng(41.0082, 28.9784),
    zoom: 13,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeVoiceCallRecoveryController();

    _ownsRideController = widget.rideController == null;
    rideController =
        widget.rideController ??
        PassengerRideController(
          gateway: RideLifecycleService(),
          repository: FirestoreRideRepository(),
          authenticatedUserId: () => FirebaseAuth.instance.currentUser?.uid,
        );
    routeLoader = widget.routeLoader ?? RouteService().getRoute;

    locationAccess = widget.locationAccess ?? LocationAccessService();

    rideController.addListener(_refreshRide);
    _initializePassengerPushTargetLifecycle();

    final injectedLiveTrackingController = widget.liveTrackingController;

    if (injectedLiveTrackingController != null) {
      liveTrackingController = injectedLiveTrackingController;
    } else if (_ownsRideController) {
      _ownsLiveTrackingController = true;
      liveTrackingController = PassengerRideLiveTrackingController(
        rideListenable: rideController,
        rideId: () => rideController.ride?.rideId,
        rideStatus: () => rideController.ride?.status,
        gateway: RideLiveTrackingService(),
      );
    }

    liveTrackingController?.addListener(_refreshLiveTracking);
    liveTrackingController?.start();

    final injectedNearbyDriverController = widget.nearbyDriverController;

    if (injectedNearbyDriverController != null) {
      nearbyDriverController = injectedNearbyDriverController;
    } else if (_ownsRideController) {
      _ownsNearbyDriverController = true;
      final nearbyDriverService = NearbyPassengerDriverService();
      nearbyDriverController = PassengerNearbyDriverController(
        rideListenable: rideController,
        rideId: () => rideController.ride?.rideId,
        rideStatus: () => rideController.ride?.status,
        loader: nearbyDriverService.load,
      );
    }

    nearbyDriverController?.addListener(_refreshNearbyDrivers);
    nearbyDriverController?.start();

    final injectedMidtripRouteChangeController =
        widget.midtripRouteChangeController;

    if (injectedMidtripRouteChangeController != null) {
      midtripRouteChangeController = injectedMidtripRouteChangeController;
    } else if (_ownsRideController) {
      _ownsMidtripRouteChangeController = true;
      midtripRouteChangeController = RideMidtripRouteChangeController(
        rideListenable: rideController,
        rideId: () => rideController.ride?.rideId,
        rideStatus: () => rideController.ride?.status,
        eventGateway: FirestoreRideDropoffChangeProposalEventRepository(),
        routeChangeGateway: RideMidtripRouteChangeService(),
      );
    }

    midtripRouteChangeController?.start();

    rideController.recover();
    if (_ownsRideController) {
      _authSubscription = FirebaseAuth.instance.userChanges().skip(1).listen((
        user,
      ) {
        _voiceCallRecoveryController?.authChanged();
        unawaited(rideController.authChanged(user?.uid));
        _passengerPushTargetLifecycle?.setEligible(user != null);
      });
    }
  }

  void _initializePassengerPushTargetLifecycle() {
    if (!_ownsRideController) {
      return;
    }

    try {
      final platform = resolvePassengerPushTargetPlatform();

      if (platform == null) {
        return;
      }

      final lifecycle = PassengerPushTargetLifecycleController(
        registration: PassengerPushTargetRegistrationService(),
        platform: platform,
      );

      _passengerPushTargetLifecycle = lifecycle;
      _ownsPassengerPushTargetLifecycle = true;

      lifecycle.setEligible(FirebaseAuth.instance.currentUser != null);
    } catch (_) {
      // Push registration is only a wake-up optimization. Home startup and
      // canonical ride polling must remain available when registration fails.
      _passengerPushTargetLifecycle = null;
      _ownsPassengerPushTargetLifecycle = false;
    }
  }

  void _initializeVoiceCallRecoveryController() {
    final injected = widget.voiceCallRecoveryController;

    if (injected != null) {
      _voiceCallRecoveryController = injected;
      _ownsVoiceCallRecoveryController = false;
    } else if (widget.rideController == null) {
      _voiceCallRecoveryController = RideVoiceCallRecoveryController(
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _voiceCallRecoveryController?.appResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeVoiceCallRecoveryController();
    rideController.removeListener(_refreshRide);
    liveTrackingController?.removeListener(_refreshLiveTracking);
    if (_ownsLiveTrackingController) {
      liveTrackingController?.dispose();
    }
    nearbyDriverController?.removeListener(_refreshNearbyDrivers);
    if (_ownsNearbyDriverController) {
      nearbyDriverController?.dispose();
    }
    if (_ownsMidtripRouteChangeController) {
      midtripRouteChangeController?.dispose();
    }
    _passengerPushTargetLifecycle?.setEligible(false);
    if (_ownsPassengerPushTargetLifecycle) {
      _passengerPushTargetLifecycle?.dispose();
    }
    _authSubscription?.cancel();
    if (_ownsRideController) rideController.dispose();
    super.dispose();
  }

  void _refreshRide() {
    if (mounted) setState(() {});
  }

  Future<bool> _authenticate() async {
    if (widget.authenticate case final authenticate?) return authenticate();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      await user.getIdToken(true);
      return true;
    } on FirebaseAuthException {
      return false;
    }
  }

  void _refreshMarkers() {
    Marker? userMarker;

    // Kullanıcı markerını koru
    for (final marker in _markers) {
      if (marker.markerId.value == "me") {
        userMarker = marker;
        break;
      }
    }

    // Tüm markerları temizle
    _markers.clear();

    // Kullanıcı markerını tekrar ekle
    if (userMarker != null) {
      _markers.add(userMarker);
    }

    // Pickup & Destination markerlarını ekle
    _markers.addAll(
      routeMarkerService.createRouteMarkers(
        pickup: pickupAddress,
        destination: destinationAddress,
      ),
    );

    _applyNearbyDriverMarkers();
    _applyLiveDriverMarker();
  }

  void _refreshLiveTracking() {
    if (!mounted) {
      return;
    }

    setState(() {
      _applyLiveDriverMarker();
    });
  }

  void _refreshNearbyDrivers() {
    if (!mounted) {
      return;
    }

    setState(() {
      _applyNearbyDriverMarkers();
      _applyLiveDriverMarker();
    });
  }

  void _applyNearbyDriverMarkers() {
    _markers.removeWhere(
      (marker) => marker.markerId.value.startsWith('nearby_driver_'),
    );

    final controller = nearbyDriverController;

    if (controller == null || !controller.isActive) {
      return;
    }

    for (var index = 0; index < controller.projections.length; index++) {
      final projection = controller.projections[index];

      _markers.add(
        Marker(
          markerId: MarkerId('nearby_driver_$index'),
          position: LatLng(projection.latitude, projection.longitude),
          infoWindow: const InfoWindow(title: 'Yakındaki sürücü'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
        ),
      );
    }
  }

  void _applyLiveDriverMarker() {
    _markers.removeWhere(
      (marker) => marker.markerId.value == 'active_ride_driver',
    );

    final trackingController = liveTrackingController;

    if (trackingController == null) {
      return;
    }

    final location = trackingController.driverLocation;

    if (location == null) {
      return;
    }

    _markers.add(
      Marker(
        markerId: const MarkerId('active_ride_driver'),
        position: LatLng(location.latitude, location.longitude),
        infoWindow: const InfoWindow(title: 'Sürücünüz'),
      ),
    );
  }

  String? _liveTrackingStatusText() {
    final ride = rideController.ride;
    final trackingController = liveTrackingController;

    if (ride == null ||
        trackingController == null ||
        !trackingController.isActive) {
      return null;
    }

    return passengerActiveRideArrivalContextText(
      status: ride.status,
      isUpdating: trackingController.isUpdating,
      etaSeconds: trackingController.etaSeconds,
    );
  }

  Future<void> _getCurrentLocation() async {
    if (_locationLoading) return;

    setState(() {
      _locationLoading = true;
      _locationIssue = null;
    });

    LocationAccessResult result;

    try {
      result = await locationAccess.currentLocation();
    } catch (_) {
      result = const LocationAccessResult.failed(
        LocationAccessIssue.unavailable,
      );
    }

    if (!mounted) return;

    final location = result.location;

    if (!result.granted || location == null) {
      setState(() {
        _locationLoading = false;
        _locationIssue = result.issue ?? LocationAccessIssue.unavailable;
      });
      return;
    }

    final userLocation = LatLng(location.latitude, location.longitude);

    if (pickupAddress == null) {}

    if (!mounted) return;

    setState(() {
      _locationLoading = false;
      _locationIssue = null;

      _markers.removeWhere((marker) => marker.markerId.value == "me");

      _markers.add(
        Marker(
          markerId: const MarkerId("me"),
          position: userLocation,
          infoWindow: const InfoWindow(title: "Benim Konumum"),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );

      _refreshMarkers();
    });

    try {
      await mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(userLocation, 17),
      );
    } catch (_) {
      // Konum hazir; kamera hareketi kritik degildir.
    }
  }

  Future<void> _handleLocationIssueAction() async {
    final issue = _locationIssue;

    if (issue == null || _locationLoading) {
      return;
    }

    switch (issue) {
      case LocationAccessIssue.serviceDisabled:
        await locationAccess.openLocationSettings();
        return;

      case LocationAccessIssue.permissionDeniedForever:
        await locationAccess.openAppSettings();
        return;

      case LocationAccessIssue.permissionDenied:
      case LocationAccessIssue.unavailable:
        await _getCurrentLocation();
        return;
    }
  }

  void _updateRoutePreview() {
    _polylines.clear();
    _routeDistanceMeters = null;
    _routeDurationSeconds = null;

    final pickup = pickupAddress;
    final destination = destinationAddress;
    if (pickup == null || destination == null) return;

    _polylines.add(
      Polyline(
        polylineId: const PolylineId("route_preview"),
        color: Colors.blue,
        width: 6,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        points: [
          LatLng(pickup.latitude, pickup.longitude),
          LatLng(destination.latitude, destination.longitude),
        ],
      ),
    );
  }

  Future<void> _searchTaxi() async {
    if (_isRouteLoading ||
        rideController.loading ||
        rideController.mutating ||
        rideController.ride != null) {
      return;
    }

    final pickup = pickupAddress;
    final destination = destinationAddress;
    if (pickup == null || destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Lütfen alınış ve varış adreslerini seçin."),
        ),
      );
      return;
    }

    setState(() {
      _isRouteLoading = true;
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
    });

    try {
      if (!await _authenticate()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Oturum doğrulanamadı. Lütfen yeniden giriş yapın."),
          ),
        );
        return;
      }

      final route = await routeLoader(
        pickup: LatLng(pickup.latitude, pickup.longitude),
        destination: LatLng(destination.latitude, destination.longitude),
      );

      if (!mounted) return;

      setState(() {
        _polylines
          ..clear()
          ..add(
            Polyline(
              polylineId: const PolylineId("real_route"),
              color: Colors.blue,
              width: 6,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
              points: route.points,
            ),
          );
        _routeDistanceMeters = route.distanceMeters;
        _routeDurationSeconds = route.durationSeconds;
      });

      await _focusRoutePoints(route.points);
      if (!mounted) return;

      await rideController.create(
        pickup: RideLocation(
          latitude: pickup.latitude,
          longitude: pickup.longitude,
          addressLabel: pickup.title,
        ),
        dropoff: RideLocation(
          latitude: destination.latitude,
          longitude: destination.longitude,
          addressLabel: destination.title,
        ),
      );
      if (mounted && rideController.errorMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(rideController.errorMessage!)));
      }
    } on RouteServiceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Rota oluşturulurken beklenmeyen bir sorun oluştu."),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRouteLoading = false;
        });
      }
    }
  }

  Future<void> _focusRoutePoints(List<LatLng> routePoints) async {
    if (routePoints.isEmpty) return;

    final controller = mapController;
    if (controller == null) return;

    final points = List<LatLng>.from(routePoints);

    var minLatitude = points.first.latitude;
    var maxLatitude = points.first.latitude;
    var minLongitude = points.first.longitude;
    var maxLongitude = points.first.longitude;

    for (final point in points.skip(1)) {
      minLatitude = math.min(minLatitude, point.latitude);
      maxLatitude = math.max(maxLatitude, point.latitude);
      minLongitude = math.min(minLongitude, point.longitude);
      maxLongitude = math.max(maxLongitude, point.longitude);
    }

    try {
      const minimumSpan = 0.0001;
      if (maxLatitude - minLatitude < minimumSpan &&
          maxLongitude - minLongitude < minimumSpan) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(points.first, 16),
        );
        return;
      }

      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLatitude, minLongitude),
            northeast: LatLng(maxLatitude, maxLongitude),
          ),
          110,
        ),
      );
    } catch (_) {
      debugPrint("Rota kamera görünümü güncellenemedi.");
    }
  }

  Future<void> _focusSelectedRoute() async {
    final pickup = pickupAddress;
    final destination = destinationAddress;
    if (pickup == null || destination == null) return;

    await _focusRoutePoints([
      LatLng(pickup.latitude, pickup.longitude),
      LatLng(destination.latitude, destination.longitude),
    ]);
  }

  Future<void> _selectPickupAddress() async {
    final AddressModel? result = await Navigator.push<AddressModel>(
      context,
      MaterialPageRoute(builder: (_) => const SearchAddressScreen()),
    );

    if (result == null) return;
    if (!mounted) return;

    setState(() {
      pickupAddress = result;
      _updateRoutePreview();
    });

    if (destinationAddress == null) {
      await mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(result.latitude, result.longitude),
          16,
        ),
      );
    } else {
      await _focusSelectedRoute();
    }
  }

  Future<void> _selectDestinationAddress() async {
    final AddressModel? result = await Navigator.push<AddressModel>(
      context,
      MaterialPageRoute(builder: (_) => const SearchAddressScreen()),
    );

    if (result == null) return;
    if (!mounted) return;

    setState(() {
      destinationAddress = result;
      _refreshMarkers();
      _updateRoutePreview();
    });

    if (pickupAddress == null) {
      await mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(result.latitude, result.longitude),
          16,
        ),
      );
    } else {
      await _focusSelectedRoute();
    }
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
      appBar: AppBar(title: const Text("YoldaAl Taksi"), centerTitle: true),
      body: Stack(
        children: [
          YoldaAlMap(
            initialPosition: _initialPosition,
            markers: _markers,
            polylines: _polylines,
            onTap: (_) {},

            onMapCreated: (GoogleMapController controller) async {
              mapController = controller;
              await _getCurrentLocation();
            },
          ),
          if (!rideController.loading && rideController.ride == null)
            RideRequestPanel(
              pickupText: pickupAddress?.title,
              destinationText: destinationAddress?.title,
              onPickupTap: _selectPickupAddress,
              onDestinationTap: _selectDestinationAddress,
              onSearchPressed: _searchTaxi,
              isLoading: _isRouteLoading || rideController.mutating,
            ),

          if (_routeDistanceMeters != null && _routeDurationSeconds != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 108,
              child: SafeArea(
                top: false,
                child: RouteSummaryCard(
                  distanceMeters: _routeDistanceMeters!,
                  durationSeconds: _routeDurationSeconds!,
                ),
              ),
            ),

          if (rideController.ride case final ride?)
            Positioned(
              left: 16,
              right: 16,
              bottom: 108,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_liveTrackingStatusText() case final statusText?)
                      Card(
                        key: const ValueKey('passenger-live-tracking-status'),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on_outlined),
                              const SizedBox(width: 8),
                              Expanded(child: Text(statusText)),
                            ],
                          ),
                        ),
                      ),
                    CanonicalRideCard(
                      ride: ride,
                      driver: false,
                      loading: rideController.mutating,
                      onCancel: ride.status.passengerCanCancel
                          ? rideController.cancel
                          : null,
                      onDismiss: ride.status.isTerminal
                          ? rideController.dismissTerminal
                          : null,
                    ),
                    if (ride.status == RideStatus.driverEnRoute ||
                        ride.status == RideStatus.driverArrived ||
                        ride.status == RideStatus.inProgress ||
                        ride.status.isTerminal) ...[
                      const SizedBox(height: 8),
                      RideChatPanel(
                        key: ValueKey('passenger-ride-chat-${ride.rideId}'),
                        rideId: ride.rideId,
                        status: ride.status,
                        viewerRole: RideChatSenderRole.passenger,
                        gateway: widget.chatGateway,
                        requestIdGenerator:
                            widget.chatRequestIdGenerator ??
                            secureRideRequestId,
                      ),
                    ],
                    if (ride.status == RideStatus.inProgress &&
                        midtripRouteChangeController != null) ...[
                      const SizedBox(height: 8),
                      RideMidtripRouteChangePanel(
                        key: ValueKey(
                          'passenger-midtrip-route-change-${ride.rideId}',
                        ),
                        rideId: ride.rideId,
                        controller: midtripRouteChangeController!,
                        selectDropoff: _selectMidtripDropoff,
                      ),
                    ],
                    if (ride.status == RideStatus.driverEnRoute ||
                        ride.status == RideStatus.driverArrived ||
                        ride.status == RideStatus.inProgress) ...[
                      const SizedBox(height: 8),
                      RideActiveSupportPanel(
                        key: ValueKey(
                          'passenger-active-support-${ride.rideId}',
                        ),
                        rideId: ride.rideId,
                        gateway: widget.activeSupportGateway,
                        requestIdGenerator:
                            widget.supportRequestIdGenerator ??
                            secureRideRequestId,
                      ),
                    ],
                  ],
                ),
              ),
            ),

          HomeBottomPanel(
            onHistoryTap: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const RideHistoryScreen()),
              );
            },
            onDriverTap: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const DriverCenterScreen()),
              );
            },
            onProfileTap: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder:
                      widget.profileScreenBuilder ??
                      (_) => ProfileScreen(
                        phoneNumber: FirebaseAuth.instanceFor(
                          app: Firebase.app(),
                        ).currentUser?.phoneNumber,
                      ),
                ),
              );
            },
          ),
          if (_locationIssue case final issue?)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: SafeArea(
                bottom: false,
                child: LocationAccessBanner(
                  key: const ValueKey('home-location-access-banner'),
                  issue: issue,
                  onAction: () {
                    unawaited(_handleLocationIssueAction());
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
