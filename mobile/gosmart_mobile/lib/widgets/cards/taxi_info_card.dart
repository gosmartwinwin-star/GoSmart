import 'package:flutter/material.dart';

import '../../core/buttons/gosmart_button.dart';
import '../../core/cards/gosmart_card.dart';
import '../../core/spacing/gosmart_spacing.dart';
import '../../core/typography/gosmart_typography.dart';
import '../../models/taxi_model.dart';

class TaxiInfoCard extends StatelessWidget {
  final TaxiModel taxi;

  final VoidCallback onRequestTaxi;

  const TaxiInfoCard({
    super.key,
    required this.taxi,
    required this.onRequestTaxi,
  });

  @override
  Widget build(BuildContext context) {
    return GoSmartCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Text(
            taxi.driverName,
            style: GoSmartTypography.title,
          ),

          const SizedBox(height: GoSmartSpacing.sm),

          Text(
            taxi.vehicleType,
            style: GoSmartTypography.body,
          ),

          const SizedBox(height: GoSmartSpacing.xs),

          Text(
            taxi.plateNumber,
            style: GoSmartTypography.caption,
          ),

          const SizedBox(height: GoSmartSpacing.sm),

          Text(
            "⭐ ${taxi.rating}",
            style: GoSmartTypography.body,
          ),

          const SizedBox(height: GoSmartSpacing.lg),

          GoSmartButton(
            text: "TAKSİ ÇAĞIR",
            onPressed: onRequestTaxi,
          ),
        ],
      ),
    );
  }
}
