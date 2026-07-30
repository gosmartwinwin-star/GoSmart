import 'package:google_maps_flutter/google_maps_flutter.dart';

class PolylineService {
  /// Google Encoded Polyline formatını
  /// List<LatLng> haline dönüştürür.
  List<LatLng> decode(String encoded) {
    List<LatLng> points = [];

    int index = 0;
    int latitude = 0;
    int longitude = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;

      while (true) {
        int byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;

        if (byte < 0x20) break;
      }

      int deltaLatitude =
          (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      latitude += deltaLatitude;

      shift = 0;
      result = 0;

      while (true) {
        int byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;

        if (byte < 0x20) break;
      }

      int deltaLongitude =
          (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      longitude += deltaLongitude;

      points.add(
        LatLng(
          latitude / 1E5,
          longitude / 1E5,
        ),
      );
    }

    return points;
  }
}