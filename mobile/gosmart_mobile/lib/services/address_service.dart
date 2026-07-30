import '../models/address_model.dart';

class AddressService {

  static List<AddressModel> getAddresses() {

    return const [

      AddressModel(
        id: "1",
        title: "GoSmart Merkez",
        description: "İstanbul",
        latitude: 41.0105,
        longitude: 28.9717,
      ),

      AddressModel(
        id: "2",
        title: "İstanbul Havalimanı",
        description: "Arnavutköy",
        latitude: 41.2753,
        longitude: 28.7519,
      ),

      AddressModel(
        id: "3",
        title: "Taksim Meydanı",
        description: "Beyoğlu",
        latitude: 41.0369,
        longitude: 28.9850,
      ),

      AddressModel(
        id: "4",
        title: "Kadıköy İskele",
        description: "Kadıköy",
        latitude: 40.9917,
        longitude: 29.0277,
      ),

      AddressModel(
        id: "5",
        title: "Galata Kulesi",
        description: "Beyoğlu",
        latitude: 41.0256,
        longitude: 28.9744,
      ),

    ];
  }
}