import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../../controllers/taxi_controller.dart';
import '../../models/taxi_model.dart';
import '../../services/marker_service.dart';
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

  final Set<Marker> _markers = {};

  TaxiModel? selectedTaxi;

  final CameraPosition _initialPosition = const CameraPosition(
    target: LatLng(41.0082, 28.9784),
    zoom: 13,
  );

  @override
  void initState() {
    super.initState();

    debugPrint("HomeScreen Açıldı");

    taxiController.loadTaxis();

    _refreshTaxiMarkers();

    taxiController.startSimulation(() {
      if (!mounted) return;

      setState(() {
        _refreshTaxiMarkers();
      });
    });
  }

  @override
  void dispose() {
    taxiController.stopSimulation();
    super.dispose();
  }

  void _refreshTaxiMarkers() {
    _markers.removeWhere(
      (marker) => marker.markerId.value != "me",
    );

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
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    final LatLng userLocation = LatLng(
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
          "Adres arama ekranı bir sonraki adımda eklenecek.",
        ),
      ),
    );
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
            onMapCreated: (GoogleMapController controller) async {
              mapController = controller;
              await _getCurrentLocation();
            },
          ),

          /// Taksi seçili değilse yolculuk paneli göster
          if (selectedTaxi == null)
            RideRequestPanel(
              onPickupTap: () {
                debugPrint("Alınış noktası seçilecek");
              },
              onDestinationTap: () {
                debugPrint("Varış noktası seçilecek");
              },
              onSearchPressed: _searchTaxi,
            ),

          /// Taksi seçildiyse bilgi kartını göster
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

                  ScaffoldMessenger.of(context).showSnackBar(
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