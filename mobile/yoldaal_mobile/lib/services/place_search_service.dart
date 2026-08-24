import '../application/place/place_search_gateway.dart';
import '../core/firebase/firebase_functions_registry.dart';
import '../application/ride/ride_gateway.dart';
import '../models/address_model.dart';
import 'ride_lifecycle_service.dart';

class PlaceSearchService implements PlaceSearchGateway {
  PlaceSearchService({RideCallableInvoker? invoker}) : _invoker = invoker;

  static const minInputLength = 3;
  static const maxInputLength = 120;
  static const maxSessionTokenLength = 36;
  static const maxPlaceIdLength = 256;

  RideCallableInvoker? _invoker;

  RideCallableInvoker get _callableInvoker =>
      _invoker ??= FirebaseRideCallableInvoker();

  @override
  Future<List<PlaceSearchSuggestion>> search({
    required String input,
    required String sessionToken,
  }) async {
    final normalizedInput = _validateSearchInput(input);
    final normalizedToken = _validateSessionToken(sessionToken);

    final data = await _callableInvoker.call(FirebaseFunctionsRegistry.searchPlaces, {
      'input': normalizedInput,
      'sessionToken': normalizedToken,
    });

    final rawSuggestions = data['suggestions'];

    if (rawSuggestions is! List) {
      _invalidResponse();
    }

    return rawSuggestions
        .map<PlaceSearchSuggestion>(_parseSuggestion)
        .toList(growable: false);
  }

  @override
  Future<AddressModel> resolve({
    required String placeId,
    required String sessionToken,
  }) async {
    final normalizedPlaceId = _validatePlaceId(placeId);
    final normalizedToken = _validateSessionToken(sessionToken);

    final data = await _callableInvoker.call(FirebaseFunctionsRegistry.resolvePlace, {
      'placeId': normalizedPlaceId,
      'sessionToken': normalizedToken,
    });

    final place = _readMap(data['place']);

    final id = _readRequiredString(place, 'id');
    final title = _readRequiredString(place, 'title');

    final description = place['description'];
    if (description is! String) {
      _invalidResponse();
    }

    final latitude = _readCoordinate(place['latitude'], min: -90, max: 90);

    final longitude = _readCoordinate(place['longitude'], min: -180, max: 180);

    return AddressModel(
      id: id,
      title: title,
      description: description,
      latitude: latitude,
      longitude: longitude,
    );
  }

  static PlaceSearchSuggestion _parseSuggestion(Object? value) {
    final data = _readMap(value);

    return PlaceSearchSuggestion(
      placeId: _readRequiredString(data, 'placeId'),
      title: _readRequiredString(data, 'title'),
      description: _readString(data, 'description'),
    );
  }

  static Map<String, dynamic> _readMap(Object? value) {
    if (value is! Map) {
      _invalidResponse();
    }

    try {
      return Map<String, dynamic>.from(value);
    } catch (_) {
      _invalidResponse();
    }
  }

  static String _readRequiredString(Map<String, dynamic> data, String key) {
    final value = data[key];

    if (value is! String || value.trim().isEmpty) {
      _invalidResponse();
    }

    return value.trim();
  }

  static String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];

    if (value is! String) {
      _invalidResponse();
    }

    return value;
  }

  static double _readCoordinate(
    Object? value, {
    required double min,
    required double max,
  }) {
    if (value is! num || !value.isFinite) {
      _invalidResponse();
    }

    final coordinate = value.toDouble();

    if (coordinate < min || coordinate > max) {
      _invalidResponse();
    }

    return coordinate;
  }

  static String _validateSearchInput(String value) {
    final normalized = value.trim();

    if (normalized.length < minInputLength ||
        normalized.length > maxInputLength) {
      throw ArgumentError.value(
        value,
        'input',
        'Must contain 3 to 120 characters after trimming.',
      );
    }

    return normalized;
  }

  static String _validateSessionToken(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty ||
        normalized.length > maxSessionTokenLength ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        'sessionToken',
        'Must be a valid Places session token.',
      );
    }

    return normalized;
  }

  static String _validatePlaceId(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty || normalized.length > maxPlaceIdLength) {
      throw ArgumentError.value(
        value,
        'placeId',
        'Must be a non-empty bounded place id.',
      );
    }

    return normalized;
  }

  static Never _invalidResponse() {
    throw const RideGatewayException('invalid-response');
  }
}
