import '../../models/address_model.dart';

class PlaceSearchSuggestion {
  const PlaceSearchSuggestion({
    required this.placeId,
    required this.title,
    required this.description,
  });

  final String placeId;
  final String title;
  final String description;
}

abstract interface class PlaceSearchGateway {
  Future<List<PlaceSearchSuggestion>> search({
    required String input,
    required String sessionToken,
  });

  Future<AddressModel> resolve({
    required String placeId,
    required String sessionToken,
  });
}
