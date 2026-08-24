import 'package:flutter/material.dart';

import '../colors/yoldaal_colors.dart';

class YoldaAlTypography {
  YoldaAlTypography._();

  static const TextStyle headline1 = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.bold,
    color: YoldaAlColors.textPrimary,
  );

  static const TextStyle headline2 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: YoldaAlColors.textPrimary,
  );

  static const TextStyle title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: YoldaAlColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 16,
    color: YoldaAlColors.textPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 13,
    color: YoldaAlColors.textSecondary,
  );

  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: Colors.black,
  );
}
