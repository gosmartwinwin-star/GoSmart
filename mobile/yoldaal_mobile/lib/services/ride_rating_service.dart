import '../application/ride/ride_gateway.dart';
import '../application/ride/ride_rating_gateway.dart';
import '../core/firebase/firebase_functions_registry.dart';
import 'ride_lifecycle_service.dart';

class RideRatingService implements RideRatingGateway {
  RideRatingService({RideCallableInvoker? invoker})
    : _invoker = invoker ?? FirebaseRideCallableInvoker();

  final RideCallableInvoker _invoker;

  @override
  Future<RideRatingStatus> getMyRatingStatus({
    required String rideId,
  }) async {
    _validateRideId(rideId);

    final data = await _call(
      FirebaseFunctionsRegistry.getMyRideRatingStatus,
      {'rideId': rideId},
    );

    return _parseStatus(data, expectedRideId: rideId);
  }

  @override
  Future<RideRatingStatus> submitRating({
    required String rideId,
    required int rating,
    required String requestId,
  }) async {
    _validateRideId(rideId);
    _validateRating(rating);
    _validateRequestId(requestId);

    final data = await _call(
      FirebaseFunctionsRegistry.submitRideRating,
      {
        'rideId': rideId,
        'rating': rating,
        'requestId': requestId,
      },
    );

    final rawRideId = data['rideId'];
    final rawRating = data['rating'];
    final rawSubmittedAtMillis = data['submittedAtMillis'];
    final rawRole = data['raterRole'];

    if (data.length != 4 ||
        rawRideId != rideId ||
        rawRating != rating ||
        rawRole is! String ||
        (rawRole != 'passenger' && rawRole != 'driver') ||
        rawSubmittedAtMillis is! int ||
        rawSubmittedAtMillis < 0) {
      throw const RideGatewayException('invalid-response');
    }

    return RideRatingStatus(
      rideId: rideId,
      hasSubmitted: true,
      rating: rating,
      submittedAt: DateTime.fromMillisecondsSinceEpoch(
        rawSubmittedAtMillis,
        isUtc: true,
      ),
    );
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    try {
      return await _invoker.call(name, payload);
    } on RideGatewayException {
      rethrow;
    } catch (_) {
      throw const RideGatewayException('invalid-response');
    }
  }

  static RideRatingStatus _parseStatus(
    Map<String, dynamic> data, {
    required String expectedRideId,
  }) {
    if (data['rideId'] != expectedRideId ||
        data['hasSubmitted'] is! bool) {
      throw const RideGatewayException('invalid-response');
    }

    final hasSubmitted = data['hasSubmitted'] as bool;

    if (!hasSubmitted) {
      if (data.length != 2) {
        throw const RideGatewayException('invalid-response');
      }

      return RideRatingStatus(
        rideId: expectedRideId,
        hasSubmitted: false,
      );
    }

    final rating = data['rating'];
    final submittedAtMillis = data['submittedAtMillis'];

    if (data.length != 4 ||
        rating is! int ||
        rating < 1 ||
        rating > 5 ||
        submittedAtMillis is! int ||
        submittedAtMillis < 0) {
      throw const RideGatewayException('invalid-response');
    }

    return RideRatingStatus(
      rideId: expectedRideId,
      hasSubmitted: true,
      rating: rating,
      submittedAt: DateTime.fromMillisecondsSinceEpoch(
        submittedAtMillis,
        isUtc: true,
      ),
    );
  }

  static void _validateRideId(String value) {
    if (value.isEmpty ||
        value.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw ArgumentError.value(value, 'rideId', 'Invalid ride id.');
    }
  }

  static void _validateRating(int value) {
    if (value < 1 || value > 5) {
      throw ArgumentError.value(value, 'rating', 'Must be between 1 and 5.');
    }
  }

  static void _validateRequestId(String value) {
    if (value.length < 16 ||
        value.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw ArgumentError.value(value, 'requestId', 'Invalid request id.');
    }
  }
}
