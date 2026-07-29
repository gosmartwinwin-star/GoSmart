import 'package:flutter/material.dart';

import '../colors/gosmart_colors.dart';
import '../radius/gosmart_radius.dart';
import '../shadows/gosmart_shadows.dart';

class GoSmartCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const GoSmartCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: GoSmartColors.surface,
        borderRadius: BorderRadius.circular(
          GoSmartRadius.lg,
        ),
        boxShadow: GoSmartShadows.card,
      ),
      child: child,
    );
  }
}