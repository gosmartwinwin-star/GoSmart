import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../../controllers/taxi_controller.dart';
import '../../models/address_model.dart';
import '../../models/taxi_model.dart';
import '../../screens/search/search_address_screen.dart';
import '../../services/marker_service.dart';
import '../../services/route_marker_service.dart';
import '../../widgets/cards/taxi_info_card.dart';
import '../../widgets/map/gosmart_map.dart';
import '../../widgets/panels/home_bottom_panel.dart';
import '../../widgets/panels/ride_request_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GoogleMapController? mapController;

  final TaxiController taxiController = TaxiController();

  final MarkerService markerService = MarkerService();

  final RouteMarkerService routeMarkerService =
      RouteMarkerService();

  final Set<Marker> _markers = {};

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

    debugPrint("HomeScreen Açıldı");

    taxiController.loadTaxis();

    _refreshMarkers();

    taxiController.startSimulation(() {
      if (!mounted) return;

      setState(() {
        _refreshMarkers();
      });
    });
  }

  @override
  void dispose() {
    taxiController.stopSimulation();
    super.dispose();
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
    _markers.addAll(
      markerService.createTaxiMarkers(
        taxis: taxiController.taxis,
        onTap: (TaxiModel taxi) {
          setState(() {
            selectedTaxi = taxi;
          });

          debugPrint("${taxi.driverName} seçildi");
        },
      ),
    );

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

    serviceEnabled =
        await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) return;

    permission =
        await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission =
          await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        return;
      }
    }

    if (permission ==
        LocationPermission.deniedForever) {
      return;
    }

    Position position =
        await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    final userLocation = LatLng(
      position.latitude,
      position.longitude,
    );

    setState(() {
      _markers.removeWhere(
        (marker) => marker.markerId.value == "me",
      );

      _markers.add(
        Marker(
          markerId: const MarkerId("me"),
          position: userLocation,
          infoWindow: const InfoWindow(
            title: "Benim Konumum",
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    });

    await mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        userLocation,
        17,
      ),
    );
  }

  void _searchTaxi() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Rota ve taksi arama sistemi bir sonraki adımda eklenecek.",
        ),
      ),
    );
  }

  Future<void> _selectPickupAddress() async {
    final AddressModel? result =
        await Navigator.push<AddressModel>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const SearchAddressScreen(),
      ),
    );

    if (result == null) return;

    setState(() {
      pickupAddress = result;
      _refreshMarkers();
    });

    debugPrint("Pickup : ${result.title}");
  }

  Future<void> _selectDestinationAddress() async {
    final AddressModel? result =
        await Navigator.push<AddressModel>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const SearchAddressScreen(),
      ),
    );

    if (result == null) return;

    setState(() {
      destinationAddress = result;
      _refreshMarkers();
    });

    debugPrint("Destination : ${result.title}");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("GoSmart Taksi"),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          GoSmartMap(
            initialPosition: _initialPosition,
            markers: _markers,
            onTap: (_) {
              setState(() {
                selectedTaxi = null;
              });
            },
            onMapCreated:
                (GoogleMapController controller) async {
              mapController = controller;
              await _getCurrentLocation();
            },
          ),

          if (selectedTaxi == null)
            RideRequestPanel(
              pickupText: pickupAddress?.title,
              destinationText: destinationAddress?.title,
              onPickupTap: _selectPickupAddress,
              onDestinationTap:
                  _selectDestinationAddress,
              onSearchPressed: _searchTaxi,
            ),

          if (selectedTaxi != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 110,
              child: TaxiInfoCard(
                taxi: selectedTaxi!,
                onRequestTaxi: () {
                  debugPrint(
                    "Taksi çağrıldı: ${selectedTaxi!.driverName}",
                  );

                  ScaffoldMessenger.of(context)
                      .showSnackBar(
                    SnackBar(
                      content: Text(
                        "${selectedTaxi!.driverName} için çağrı oluşturuldu.",
                      ),
                    ),
                  );
                },
              ),
            ),

          const HomeBottomPanel(),
        ],
      ),
    );
  }
}