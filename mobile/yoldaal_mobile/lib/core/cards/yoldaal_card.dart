import 'package:flutter/material.dart';

import '../colors/yoldaal_colors.dart';
import '../radius/yoldaal_radius.dart';
import '../shadows/yoldaal_shadows.dart';

class YoldaAlCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const YoldaAlCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: YoldaAlColors.surface,
        borderRadius: BorderRadius.circular(
          YoldaAlRadius.lg,
        ),
        boxShadow: YoldaAlShadows.card,
      ),
      child: child,
    );
  }
}
