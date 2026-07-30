import 'package:flutter/material.dart';

import '../../models/address_model.dart';

class SearchResultTile extends StatelessWidget {
  final AddressModel address;
  final VoidCallback onTap;

  const SearchResultTile({
    super.key,
    required this.address,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(
        child: Icon(Icons.location_on),
      ),
      title: Text(address.title),
      subtitle: Text(address.description),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}