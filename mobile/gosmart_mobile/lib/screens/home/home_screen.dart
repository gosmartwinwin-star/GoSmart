import 'dart:math' as math;
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../controllers/taxi_controller.dart';
import '../../controllers/passenger_ride_controller.dart';
import '../../domain/ride/canonical_ride.dart';
import '../../infrastructure/firestore/repositories/firestore_ride_repository.dart';
import '../../models/address_model.dart';
import '../../models/taxi_model.dart';
import '../../screens/search/search_address_screen.dart';
import '../../screens/driver/driver_center_screen.dart';
import '../../services/marker_service.dart';
import '../../services/route_marker_service.dart';
import '../../services/route_service.dart';
import '../../services/ride_lifecycle_service.dart';
import '../../widgets/ride/canonical_ride_card.dart';
import '../../widgets/cards/route_summary_card.dart';
import '../../widgets/cards/taxi_info_card.dart';
import '../../widgets/map/gosmart_map.dart';
import '../../widgets/panels/home_bottom_panel.dart';
import '../../widgets/panels/ride_request_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.rideController});
  final PassengerRideController? rideController;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PassengerRideController rideController;
  late final bool _ownsRideController;
  StreamSubscription<User?>? _authSubscription;
  GoogleMapController? mapController;

  final TaxiController taxiController = TaxiController();

  final MarkerService markerService = MarkerService();

  final RouteMarkerService routeMarkerService = RouteMarkerService();

  final RouteService routeService = RouteService();

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  bool _isRouteLoading = false;

  int? _routeDistanceMeters;
  int? _routeDurationSeconds;

  TaxiModel? selectedTaxi;

  AddressModel? pickupAddress;

  AddressModel? destinationAddress;

  final CameraPosition _initialPosition = const CameraPosition(
    target: LatLng(41.0082, 28.9784),
    zoom: 13,
  );

  @override
  void initState() {
    super.initState();

    _ownsRideController = widget.rideController == null;
    rideController = widget.rideController ?? PassengerRideController(gateway: RideLifecycleService(), repository: FirestoreRideRepository(), authenticatedUserId: () => FirebaseAuth.instance.currentUser?.uid);
    rideController.addListener(_refreshRide);
    rideController.recover();
    if (_ownsRideController) { _authSubscription = FirebaseAuth.instance.userChanges().skip(1).listen((user) => rideController.authChanged(user?.uid)); }

    _initializeTaxis();

    taxiController.startSimulation(() {
      if (!mounted) return;

      setState(() {
        final selectedTaxiId = selectedTaxi?.id;
        if (selectedTaxiId != null) {
          for (final taxi in taxiController.taxis) {
            if (taxi.id == selectedTaxiId) {
              selectedTaxi = taxi;
              break;
            }
          }
        }
        _refreshMarkers();
      });
    });
  }

  @override
  void dispose() {
    rideController.removeListener(_refreshRide);
    _authSubscription?.cancel();
    if (_ownsRideController) rideController.dispose();
    taxiController.stopSimulation();
    super.dispose();
  }

  void _refreshRide() { if (mounted) setState(() {}); }

  Future<void> _createCanonicalRide() async {
    final pickup = pickupAddress; final dropoff = destinationAddress;
    if (pickup == null || dropoff == null) return;
    await rideController.create(
      pickup: RideLocation(latitude: pickup.latitude, longitude: pickup.longitude, addressLabel: pickup.title),
      dropoff: RideLocation(latitude: dropoff.latitude, longitude: dropoff.longitude, addressLabel: dropoff.title),
    );
    if (mounted && rideController.errorMessage != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(rideController.errorMessage!)));
  }

  void _initializeTaxis() {
    taxiController.loadTaxisAround(
      latitude: _initialPosition.target.latitude,
      longitude: _initialPosition.target.longitude,
    );
    _refreshMarkers();
  }

  void _reloadTaxisAround({
    required double latitude,
    required double longitude,
  }) {
    taxiController.loadTaxisAround(latitude: latitude, longitude: longitude);

    if (!mounted) return;

    setState(() {
      _refreshMarkers();
    });
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

    // Taksi markerlarını ekle
    final taxiMarkers = markerService.createTaxiMarkers(
      taxis: taxiController.taxis,
      onTap: (TaxiModel taxi) {
        setState(() {
          selectedTaxi = taxi;
        });

        debugPrint("${taxi.driverName} seçildi");
      },
    );
    _markers.addAll(taxiMarkers);

    if (kDebugMode) {
      debugPrint("Taksi modeli sayısı: ${taxiController.taxis.length}");
      debugPrint("Taksi marker sayısı: ${taxiMarkers.length}");
    }

    // Pickup & Destination markerlarını ekle
    _markers.addAll(
      routeMarkerService.createRouteMarkers(
        pickup: pickupAddress,
        destination: destinationAddress,
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
    );

    final userLocation = LatLng(position.latitude, position.longitude);

    if (pickupAddress == null) {
      _reloadTaxisAround(
        latitude: userLocation.latitude,
        longitude: userLocation.longitude,
      );
    }

    if (!mounted) return;

    setState(() {
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

    await mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(userLocation, 17),
    );
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
    if (_isRouteLoading) return;

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

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Oturumunuz bulunamadı. Lütfen yeniden giriş yapın."),
        ),
      );
      return;
    }

    try {
      await user.getIdToken(true);
    } on FirebaseAuthException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Oturum doğrulanamadı. Lütfen yeniden giriş yapın."),
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
      final route = await routeService.getRoute(
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

      final distance = route.distanceMeters < 1000
          ? "${route.distanceMeters} m"
          : "${(route.distanceMeters / 1000).toStringAsFixed(1)} km";
      final durationMinutes = math.max(1, (route.durationSeconds / 60).ceil());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Rota hazır • $distance • $durationMinutes dk")),
      );
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
    final pickup = pickupAddress;
    final pickupPoint = pickup == null
        ? routePoints.first
        : LatLng(pickup.latitude, pickup.longitude);

    for (final taxi in taxiController.taxis) {
      if (taxi.online &&
          (taxi.latitude - pickupPoint.latitude).abs() <= 0.02 &&
          (taxi.longitude - pickupPoint.longitude).abs() <= 0.02) {
        points.add(LatLng(taxi.latitude, taxi.longitude));
      }
    }

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
      selectedTaxi = null;
      _updateRoutePreview();
    });

    _reloadTaxisAround(latitude: result.latitude, longitude: result.longitude);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("GoSmart Taksi"), centerTitle: true),
      body: Stack(
        children: [
          GoSmartMap(
            initialPosition: _initialPosition,
            markers: _markers,
            polylines: _polylines,
            onTap: (_) {
              setState(() {
                selectedTaxi = null;
              });
            },
            onMapCreated: (GoogleMapController controller) async {
              mapController = controller;
              await _getCurrentLocation();
            },
          ),

          if (rideController.ride == null && selectedTaxi == null)
            RideRequestPanel(
              pickupText: pickupAddress?.title,
              destinationText: destinationAddress?.title,
              onPickupTap: _selectPickupAddress,
              onDestinationTap: _selectDestinationAddress,
              onSearchPressed: _searchTaxi,
              isLoading: _isRouteLoading,
            ),

          if (rideController.ride == null && selectedTaxi != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 110,
              child: TaxiInfoCard(
                taxi: selectedTaxi!,
                onRequestTaxi: rideController.mutating ? () {} : _createCanonicalRide,
              ),
            ),

          if (_routeDistanceMeters != null &&
              _routeDurationSeconds != null &&
              selectedTaxi == null)
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
            Positioned(left: 16, right: 16, bottom: 108, child: SafeArea(top: false, child: CanonicalRideCard(
              ride: ride, driver: false, loading: rideController.mutating,
              onCancel: ride.status.passengerCanCancel ? rideController.cancel : null,
              onDismiss: ride.status.isTerminal ? rideController.dismissTerminal : null,
            ))),

          HomeBottomPanel(
            onDriverTap: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const DriverCenterScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
