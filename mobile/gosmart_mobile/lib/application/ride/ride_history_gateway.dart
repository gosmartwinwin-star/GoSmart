import '../../domain/ride/ride_history.dart';

abstract interface class RideHistoryGateway {
  Future<RideHistoryPage> loadPage({
    required RideHistoryScope scope,
    int pageSize = 20,
    RideHistoryCursor? cursor,
  });
}
