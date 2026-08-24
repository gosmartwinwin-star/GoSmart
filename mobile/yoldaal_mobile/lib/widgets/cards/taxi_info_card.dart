import 'package:flutter/material.dart';

import '../../core/buttons/yoldaal_button.dart';
import '../../core/cards/yoldaal_card.dart';
import '../../core/spacing/yoldaal_spacing.dart';
import '../../core/typography/yoldaal_typography.dart';
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
    return YoldaAlCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Text(
            taxi.driverName,
            style: YoldaAlTypography.title,
          ),

          const SizedBox(height: YoldaAlSpacing.sm),

          Text(
            taxi.vehicleType,
            style: YoldaAlTypography.body,
          ),

          const SizedBox(height: YoldaAlSpacing.xs),

          Text(
            taxi.plateNumber,
            style: YoldaAlTypography.caption,
          ),

          const SizedBox(height: YoldaAlSpacing.sm),

          Text(
            "⭐ ${taxi.rating}",
            style: YoldaAlTypography.body,
          ),

          const SizedBox(height: YoldaAlSpacing.lg),

          YoldaAlButton(
            text: "TAKSİ ÇAĞIR",
            onPressed: onRequestTaxi,
          ),
        ],
      ),
    );
  }
}
