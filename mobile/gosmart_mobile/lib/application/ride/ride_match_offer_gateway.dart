import '../../domain/ride/ride_match_offer.dart';

abstract interface class RideMatchOfferGateway {
  Future<List<RideMatchOffer>> getMyRideMatchOffers();

  Future<void> acceptRideMatchOffer({
    required RideMatchOffer offer,
    required String requestId,
  });
}
