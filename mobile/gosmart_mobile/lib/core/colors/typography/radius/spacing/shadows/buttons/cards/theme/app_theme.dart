import 'package:flutter/material.dart';

import '../colors/gosmart_colors.dart';
import '../radius/gosmart_radius.dart';
import '../typography/gosmart_typography.dart';

class GoSmartTheme {
  GoSmartTheme._();

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,

      scaffoldBackgroundColor: GoSmartColors.background,

      colorScheme: ColorScheme.fromSeed(
        seedColor: GoSmartColors.primary,
        brightness: Brightness.light,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: GoSmartColors.surface,
        foregroundColor: GoSmartColors.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),

      cardColor: GoSmartColors.surface,

      dividerColor: GoSmartColors.divider,

      textTheme: const TextTheme(
        headlineLarge: GoSmartTypography.headline1,
        headlineMedium: GoSmartTypography.headline2,
        titleLarge: GoSmartTypography.title,
        bodyLarge: GoSmartTypography.body,
        bodyMedium: GoSmartTypography.body,
        bodySmall: GoSmartTypography.caption,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: GoSmartColors.primary,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              GoSmartRadius.md,
            ),
          ),
          minimumSize: const Size(double.infinity, 54),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: GoSmartColors.searchBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            GoSmartRadius.md,
          ),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}