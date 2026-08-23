import 'package:flutter/material.dart';

import '../colors/yoldaal_colors.dart';

class YoldaAlShadows {
  YoldaAlShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(
      color: YoldaAlColors.shadow,
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];
}
