import '../application/ride/ride_gateway.dart';
import '../application/ride/ride_match_offer_gateway.dart';
import '../core/firebase/firebase_functions_registry.dart';
import '../domain/ride/ride_match_offer.dart';
import 'ride_lifecycle_service.dart';

class RideMatchOfferException implements Exception {
  const RideMatchOfferException(this.code, {this.reason});

  final String code;
  final String? reason;
}

class RideMatchOfferService implements RideMatchOfferGateway {
  RideMatchOfferService({RideCallableInvoker? invoker})
    : _invoker = invoker ?? FirebaseRideCallableInvoker();

  static const maxOffers = 3;

  static const _safeCodes = <String>{
    'unauthenticated',
    'invalid-argument',
    'permission-denied',
    'failed-precondition',
    'already-exists',
    'not-found',
    'unavailable',
    'internal',
    'invalid-response',
  };

  static const _safeReasons = <String>{
    'driver_profile_required',
    'driver_profile_not_approved',
    'subscription_required',
    'driver_active_ride_exists',
    'active_return_route_required',
    'active_return_route_invalid',
    'active_return_route_expired',
    'invalid_ride_match_offer_payload',
    'ride_match_offer_required',
    'ride_match_offer_not_active',
    'ride_match_offer_mismatch',
    'ride_match_offer_stale',
    'ride_match_offer_route_changed',
    'ride_match_offer_expired',
    'ride_match_offer_invalid',
    'stale_ride_version',
    'active_ride_pointer_inconsistent',
    'invalid_request_id',
    'invalid_ride_id',
    'invalid_ride_version',
  };

  final RideCallableInvoker _invoker;

  @override
  Future<List<RideMatchOffer>> getMyRideMatchOffers() async {
    try {
      final response = await _invoke(
        FirebaseFunctionsRegistry.getMyRideMatchOffers,
        const {},
      );

      if (response.length != 1 || !response.containsKey('offers')) {
        throw const FormatException('Invalid ride match offer response.');
      }

      final rawOffers = response['offers'];

      if (rawOffers is! List || rawOffers.length > maxOffers) {
        throw const FormatException('Invalid ride match offer response.');
      }

      final offers = <RideMatchOffer>[];
      final rideIds = <String>{};

      for (final rawOffer in rawOffers) {
        if (rawOffer is! Map) {
          throw const FormatException('Invalid ride match offer item.');
        }

        final offer = RideMatchOffer.fromMap(
          Map<String, dynamic>.from(rawOffer),
        );

        if (!rideIds.add(offer.rideId)) {
          throw const FormatException('Duplicate ride match offer.');
        }

        offers.add(offer);
      }

      return List<RideMatchOffer>.unmodifiable(offers);
    } on RideMatchOfferException {
      rethrow;
    } catch (_) {
      throw const RideMatchOfferException('invalid-response');
    }
  }

  @override
  Future<void> acceptRideMatchOffer({
    required RideMatchOffer offer,
    required String requestId,
  }) async {
    if (!_validRequestId(requestId)) {
      throw const RideMatchOfferException(
        'invalid-argument',
        reason: 'invalid_request_id',
      );
    }

    try {
      final response = await _invoke(FirebaseFunctionsRegistry.acceptRide, {
        'rideId': offer.rideId,
        'requestId': requestId,
        'expectedVersion': offer.rideVersion,
      });

      final returnedRideId = response['rideId'];
      final returnedStatus = response['status'];
      final returnedVersion = _positiveInteger(response['version']);

      if (returnedRideId != offer.rideId ||
          returnedStatus != 'driverEnRoute' ||
          returnedVersion != offer.rideVersion + 1) {
        throw const FormatException('Invalid accept ride response.');
      }
    } on RideMatchOfferException {
      rethrow;
    } catch (_) {
      throw const RideMatchOfferException('invalid-response');
    }
  }

  Future<Map<String, dynamic>> _invoke(
    String name,
    Map<String, dynamic> payload,
  ) async {
    try {
      return await _invoker.call(name, payload);
    } on RideGatewayException catch (error) {
      throw RideMatchOfferException(
        _safeCode(error.code),
        reason: _safeReason(error.reason),
      );
    } catch (_) {
      throw const RideMatchOfferException('unavailable');
    }
  }

  static bool _validRequestId(String value) =>
      value.length >= 16 &&
      value.length <= 128 &&
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);

  static int? _positiveInteger(Object? value) {
    if (value is int) {
      return value > 0 ? value : null;
    }

    if (value is num &&
        value.isFinite &&
        value == value.roundToDouble() &&
        value > 0) {
      return value.toInt();
    }

    return null;
  }

  static String _safeCode(String code) =>
      _safeCodes.contains(code) ? code : 'unknown';

  static String? _safeReason(String? reason) =>
      reason != null && _safeReasons.contains(reason) ? reason : null;
}
