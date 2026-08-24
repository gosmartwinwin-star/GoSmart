import '../../domain/return_route/geo_coordinate.dart';

abstract final class GeoPolylineDecoder {
  static List<GeoCoordinate> decode(String encodedPolyline) {
    if (encodedPolyline.isEmpty) {
      throw const FormatException('Encoded polyline boş olamaz.');
    }

    var index = 0;
    var latitude = 0;
    var longitude = 0;
    final points = <GeoCoordinate>[];

    int readDelta() {
      var result = 0;
      var shift = 0;
      while (true) {
        if (index >= encodedPolyline.length || shift > 30) {
          throw const FormatException('Encoded polyline geçersiz.');
        }
        final value = encodedPolyline.codeUnitAt(index++) - 63;
        if (value < 0 || value > 63) {
          throw const FormatException('Encoded polyline geçersiz.');
        }
        result |= (value & 0x1f) << shift;
        if (value < 0x20) break;
        shift += 5;
      }
      return (result & 1) == 1 ? ~(result >> 1) : result >> 1;
    }

    try {
      while (index < encodedPolyline.length) {
        latitude += readDelta();
        longitude += readDelta();
        points.add(
          GeoCoordinate(latitude: latitude / 1e5, longitude: longitude / 1e5),
        );
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Encoded polyline geçersiz.');
    }

    if (points.length < 2) {
      throw const FormatException('Polyline en az iki nokta içermelidir.');
    }
    return List<GeoCoordinate>.unmodifiable(points);
  }
}
