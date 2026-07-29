import 'package:flutter/material.dart';

import '../core/buttons/gosmart_button.dart';
import '../core/cards/gosmart_card.dart';
import '../core/spacing/gosmart_spacing.dart';
import '../core/typography/gosmart_typography.dart';

class RideRequestPanel extends StatelessWidget {
  const RideRequestPanel({
    super.key,
    required this.onPickupTap,
    required this.onDestinationTap,
    required this.onSearchTaxi,
  });

  final VoidCallback onPickupTap;
  final VoidCallback onDestinationTap;
  final VoidCallback onSearchTaxi;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GoSmartCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Yolculuğunu Planla",
                  style: GoSmartTypography.title,
                ),

                const SizedBox(height: GoSmartSpacing.lg),

                InkWell(
                  onTap: onPickupTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.my_location),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Nereden alınacaksınız?",
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: GoSmartSpacing.md),

                InkWell(
                  onTap: onDestinationTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.location_on_outlined),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Nereye gideceksiniz?",
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: GoSmartSpacing.lg),

                GoSmartButton(
                  text: "TAKSİ ARA",
                  onPressed: onSearchTaxi,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}