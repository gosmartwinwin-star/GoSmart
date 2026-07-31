import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/infrastructure/polyline/geo_polyline_decoder.dart';

void main() {
  const encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

  test('bilinen Google polyline koordinatlarını çözer', () {
    final points = GeoPolylineDecoder.decode(encoded);
    expect(points, hasLength(3));
    expect(points[0].latitude, closeTo(38.5, 0.00001));
    expect(points[0].longitude, closeTo(-120.2, 0.00001));
    expect(points[1].latitude, closeTo(40.7, 0.00001));
    expect(points[1].longitude, closeTo(-120.95, 0.00001));
    expect(points[2].latitude, closeTo(43.252, 0.00001));
    expect(points[2].longitude, closeTo(-126.453, 0.00001));
  });

  test('boş polyline reddedilir', () {
    expect(() => GeoPolylineDecoder.decode(''), throwsFormatException);
  });

  test('yarım polyline reddedilir', () {
    expect(() => GeoPolylineDecoder.decode('_p~iF'), throwsFormatException);
  });

  test('tek noktalı polyline reddedilir', () {
    expect(
      () => GeoPolylineDecoder.decode('_p~iF~ps|U'),
      throwsFormatException,
    );
  });

  test('sonuç listesi değiştirilemez', () {
    final points = GeoPolylineDecoder.decode(encoded);
    expect(() => points.add(points.first), throwsUnsupportedError);
  });

  test('aynı input deterministik aynı koordinatları üretir', () {
    expect(
      GeoPolylineDecoder.decode(encoded),
      GeoPolylineDecoder.decode(encoded),
    );
  });
}
