import 'package:flutter/material.dart';

import '../../controllers/address_controller.dart';
import '../../models/address_model.dart';
import '../../widgets/search/search_result_tile.dart';

class SearchAddressScreen extends StatefulWidget {
  const SearchAddressScreen({super.key});

  @override
  State<SearchAddressScreen> createState() =>
      _SearchAddressScreenState();
}

class _SearchAddressScreenState
    extends State<SearchAddressScreen> {
  final TextEditingController searchController =
      TextEditingController();

  final AddressController addressController =
      AddressController();

  @override
  void initState() {
    super.initState();

    addressController.load();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Widget _favoriteTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(.15),
        child: Icon(
          icon,
          color: color,
        ),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        debugPrint(title);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Adres Ara"),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: searchController,
                autofocus: true,
                onChanged: (value) {
                  setState(() {
                    addressController.search(value);
                  });
                },
                decoration: InputDecoration(
                  hintText: "Adres veya yer ara",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            const Divider(height: 1),

            Expanded(
              child: searchController.text.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 8),

                        _favoriteTile(
                          icon: Icons.home,
                          color: Colors.blue,
                          title: "Ev",
                          subtitle: "Henüz kayıtlı değil",
                        ),

                        _favoriteTile(
                          icon: Icons.work,
                          color: Colors.orange,
                          title: "İş",
                          subtitle: "Henüz kayıtlı değil",
                        ),

                        _favoriteTile(
                          icon: Icons.favorite,
                          color: Colors.red,
                          title: "Favoriler",
                          subtitle: "Kayıtlı adresler",
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Text(
                            "Önerilen Yerler",
                            style: TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                        ),

                        ...addressController.filtered.map(
                          (AddressModel address) {
                            return SearchResultTile(
                              address: address,
                              onTap: () {
                                Navigator.pop(
                                  context,
                                  address,
                                );
                              },
                            );
                          },
                        ),
                      ],
                    )
                  : ListView.builder(
                      itemCount:
                          addressController.filtered.length,
                      itemBuilder: (context, index) {
                        final address =
                            addressController.filtered[index];

                        return SearchResultTile(
                          address: address,
                          onTap: () {
                            Navigator.pop(
                              context,
                              address,
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}