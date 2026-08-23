import 'package:flutter/material.dart';

import '../colors/yoldaal_colors.dart';
import '../radius/yoldaal_radius.dart';
import '../typography/yoldaal_typography.dart';

class YoldaAlTheme {
  YoldaAlTheme._();

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,

      scaffoldBackgroundColor: YoldaAlColors.background,

      colorScheme: ColorScheme.fromSeed(
        seedColor: YoldaAlColors.primary,
        brightness: Brightness.light,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: YoldaAlColors.surface,
        foregroundColor: YoldaAlColors.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),

      cardColor: YoldaAlColors.surface,

      dividerColor: YoldaAlColors.divider,

      textTheme: const TextTheme(
        headlineLarge: YoldaAlTypography.headline1,
        headlineMedium: YoldaAlTypography.headline2,
        titleLarge: YoldaAlTypography.title,
        bodyLarge: YoldaAlTypography.body,
        bodyMedium: YoldaAlTypography.body,
        bodySmall: YoldaAlTypography.caption,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: YoldaAlColors.primary,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              YoldaAlRadius.md,
            ),
          ),
          minimumSize: const Size(double.infinity, 54),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: YoldaAlColors.searchBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            YoldaAlRadius.md,
          ),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
