import 'package:flutter/material.dart';
import 'colors.dart';
import 'text_styles.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          onPrimary: AppColors.onPrimary,
          primaryContainer: Color(0x1F0066CC),
          onPrimaryContainer: AppColors.primary,
          secondary: AppColors.surfacePearl,
          onSecondary: AppColors.inkMuted80,
          surface: AppColors.canvas,
          onSurface: AppColors.ink,
          error: AppColors.danger,
          onError: AppColors.onPrimary,
        ),
        scaffoldBackgroundColor: AppColors.canvasParchment,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.canvasParchment,
          foregroundColor: AppColors.ink,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: AppColors.canvas,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? AppColors.onPrimary : AppColors.dividerSoft),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? AppColors.primary : AppColors.hairline),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.surfacePearl,
          selectedColor: AppColors.primary,
          labelStyle: AppTextStyles.caption.copyWith(color: AppColors.inkMuted80),
          side: const BorderSide(color: AppColors.hairline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        ),
        dividerColor: AppColors.dividerSoft,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.canvas,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9999),
            borderSide: const BorderSide(color: AppColors.hairline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9999),
            borderSide: const BorderSide(color: AppColors.hairline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9999),
            borderSide: const BorderSide(color: AppColors.primary),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      );

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primaryOnDark,
          onPrimary: AppColors.onDark,
          primaryContainer: Color(0x1F2997FF),
          onPrimaryContainer: AppColors.primaryOnDark,
          secondary: AppColors.surfaceTile2,
          onSecondary: AppColors.bodyMuted,
          surface: AppColors.surfaceTile1,
          onSurface: AppColors.bodyOnDark,
          error: AppColors.danger,
          onError: AppColors.onDark,
        ),
        scaffoldBackgroundColor: AppColors.surfaceBlack,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surfaceBlack,
          foregroundColor: AppColors.bodyOnDark,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: AppColors.surfaceTile1,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? AppColors.onDark : AppColors.bodyMuted),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? AppColors.primaryOnDark : AppColors.surfaceChipTranslucent),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.surfaceTile2,
          selectedColor: AppColors.primaryOnDark,
          labelStyle: AppTextStyles.caption.copyWith(color: AppColors.bodyMuted),
          side: const BorderSide(color: AppColors.surfaceChipTranslucent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        ),
        dividerColor: AppColors.surfaceChipTranslucent,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceTile1,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9999),
            borderSide: const BorderSide(color: AppColors.surfaceChipTranslucent),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9999),
            borderSide: const BorderSide(color: AppColors.surfaceChipTranslucent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9999),
            borderSide: const BorderSide(color: AppColors.primaryOnDark),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      );
}
