import '../models/address_model.dart';
import '../services/address_service.dart';

class AddressController {

  List<AddressModel> addresses = [];

  List<AddressModel> filtered = [];

  void load() {

    addresses = AddressService.getAddresses();

    filtered = addresses;
  }

  void search(String keyword) {

    if (keyword.isEmpty) {

      filtered = addresses;

      return;

    }

    filtered = addresses.where((address) {

      return address.title
              .toLowerCase()
              .contains(keyword.toLowerCase()) ||

          address.description
              .toLowerCase()
              .contains(keyword.toLowerCase());

    }).toList();
  }
}
