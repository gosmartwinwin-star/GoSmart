import 'package:flutter/material.dart';

class RideRequestPanel extends StatelessWidget {
  final VoidCallback onPickupTap;
  final VoidCallback onDestinationTap;
  final VoidCallback onSearchPressed;

  final String? pickupText;
  final String? destinationText;
  final bool isLoading;

  const RideRequestPanel({
    super.key,
    required this.onPickupTap,
    required this.onDestinationTap,
    required this.onSearchPressed,
    this.pickupText,
    this.destinationText,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 20,
      left: 16,
      right: 16,
      child: SafeArea(
        child: Material(
          elevation: 10,
          borderRadius: BorderRadius.circular(22),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: onPickupTap,
                  child: _AddressBox(
                    icon: Icons.my_location_rounded,
                    iconColor: Colors.green,
                    title: pickupText ?? "Nereden alınacaksınız?",
                  ),
                ),

                const SizedBox(height: 12),

                GestureDetector(
                  onTap: onDestinationTap,
                  child: _AddressBox(
                    icon: Icons.location_on_rounded,
                    iconColor: Colors.red,
                    title: destinationText ?? "Nereye gidiyorsunuz?",
                  ),
                ),

                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : onSearchPressed,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: isLoading
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text("Rota oluşturuluyor..."),
                            ],
                          )
                        : const Text("Taksi Ara"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddressBox extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;

  const _AddressBox({
    required this.icon,
    required this.iconColor,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor),

          const SizedBox(width: 14),

          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),

          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
