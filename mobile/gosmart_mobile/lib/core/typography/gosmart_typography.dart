import 'package:flutter/material.dart';

import '../colors/gosmart_colors.dart';

class GoSmartTypography {
  GoSmartTypography._();

  static const TextStyle headline1 = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.bold,
    color: GoSmartColors.textPrimary,
  );

  static const TextStyle headline2 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: GoSmartColors.textPrimary,
  );

  static const TextStyle title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: GoSmartColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 16,
    color: GoSmartColors.textPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 13,
    color: GoSmartColors.textSecondary,
  );

  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: Colors.black,
  );
}
