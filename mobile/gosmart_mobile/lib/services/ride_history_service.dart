import '../application/ride/ride_gateway.dart';
import '../application/ride/ride_history_gateway.dart';
import '../domain/ride/canonical_ride.dart';
import '../domain/ride/ride_history.dart';
import '../core/firebase/firebase_functions_registry.dart';
import 'ride_lifecycle_service.dart';

class RideHistoryService implements RideHistoryGateway {
  RideHistoryService({RideCallableInvoker? invoker})
    : _invoker = invoker ?? FirebaseRideCallableInvoker();

  final RideCallableInvoker _invoker;

  @override
  Future<RideHistoryPage> loadPage({
    required RideHistoryScope scope,
    int pageSize = 20,
    RideHistoryCursor? cursor,
  }) async {
    if (pageSize < 1 || pageSize > 20) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'Must be between 1 and 20.',
      );
    }

    try {
      final data = await _invoker.call(FirebaseFunctionsRegistry.getMyRideHistory, {
        'scope': scope.name,
        'pageSize': pageSize,
        'cursor': cursor?.toMap(),
      });

      final rawRides = data['rides'];

      if (rawRides is! List) {
        throw const FormatException('Invalid history rides.');
      }

      final rides = <CanonicalRide>[];

      for (final value in rawRides) {
        if (value is! Map) {
          throw const FormatException('Invalid history ride.');
        }

        final ride = CanonicalRide.fromMap(Map<String, dynamic>.from(value));

        if (!ride.status.isTerminal) {
          throw const FormatException('History contains non-terminal ride.');
        }

        rides.add(ride);
      }

      final rawCursor = data['nextCursor'];

      return RideHistoryPage(
        rides: List.unmodifiable(rides),
        nextCursor: rawCursor == null
            ? null
            : RideHistoryCursor.fromObject(rawCursor),
      );
    } on RideGatewayException {
      rethrow;
    } catch (_) {
      throw const RideGatewayException('invalid-response');
    }
  }
}
