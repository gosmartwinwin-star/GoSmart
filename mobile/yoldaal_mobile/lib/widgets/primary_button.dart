import 'package:flutter/material.dart';

import '../core/colors/yoldaal_colors.dart';
import '../core/radius/yoldaal_radius.dart';
import '../core/typography/yoldaal_typography.dart';

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: YoldaAlColors.primary,
          foregroundColor: YoldaAlColors.secondary,
          disabledBackgroundColor: YoldaAlColors.primary.withValues(alpha: 0.45),
          disabledForegroundColor:
              YoldaAlColors.secondary.withValues(alpha: 0.55),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(YoldaAlRadius.md),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 10),
            ],
            Text(
              text,
              style: YoldaAlTypography.button,
            ),
          ],
        ),
      ),
    );
  }
}