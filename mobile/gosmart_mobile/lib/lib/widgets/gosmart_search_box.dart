import 'package:flutter/material.dart';

import '../core/colors/gosmart_colors.dart';
import '../core/radius/gosmart_radius.dart';

class GoSmartSearchBox extends StatelessWidget {
  final VoidCallback? onTap;

  const GoSmartSearchBox({
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        GoSmartRadius.md,
      ),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: GoSmartColors.searchBackground,
          borderRadius: BorderRadius.circular(
            GoSmartRadius.md,
          ),
        ),
        child: const Row(
          children: [
            SizedBox(width: 16),
            Icon(Icons.search),
            SizedBox(width: 12),
            Text(
              "Adres veya yer ara...",
              style: TextStyle(
                color: GoSmartColors.textSecondary,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}