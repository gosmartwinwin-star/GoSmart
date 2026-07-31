import 'package:flutter/material.dart';

import '../colors/gosmart_colors.dart';

class GoSmartShadows {
  GoSmartShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(
      color: GoSmartColors.shadow,
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];
}
