import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light({bool compact = false}) =>
      _theme(AppColors.light, Brightness.light, compact);

  static ThemeData dark({bool compact = false}) =>
      _theme(AppColors.dark, Brightness.dark, compact);

  static ThemeData _theme(
    AppColors colors,
    Brightness brightness,
    bool compact,
  ) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      error: AppColors.error,
      surface: colors.surface,
      brightness: brightness,
    );

    // Normal mode fonts are clearly larger than compact across the app.
    final textTheme = TextTheme(
      headlineLarge: TextStyle(
        fontSize: compact ? 24 : 30,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        fontSize: compact ? 20 : 26,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
        letterSpacing: -0.3,
      ),
      headlineSmall: TextStyle(
        fontSize: compact ? 18 : 22,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: compact ? 17 : 21,
        fontWeight: FontWeight.w800,
        color: colors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: compact ? 14 : 17,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: compact ? 13 : 15,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: compact ? 14 : 16,
        fontWeight: FontWeight.w400,
        color: colors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: compact ? 13 : 15,
        fontWeight: FontWeight.w400,
        color: colors.textSecondary,
      ),
      bodySmall: TextStyle(
        fontSize: compact ? 11 : 13,
        fontWeight: FontWeight.w400,
        color: colors.textSecondary,
      ),
      labelLarge: TextStyle(
        fontSize: compact ? 12 : 14,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: compact ? 11 : 13,
        fontWeight: FontWeight.w600,
        color: colors.textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: compact ? 10 : 12,
        fontWeight: FontWeight.w600,
        color: colors.textSecondary,
      ),
    );

    final inputRadius = compact ? 22.0 : 28.0;
    final buttonRadius = compact ? 22.0 : 28.0;
    final buttonHeight = compact ? 48.0 : 56.0;
    final inputPadV = compact ? 12.0 : 16.0;
    final inputPadH = compact ? 14.0 : 16.0;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.background,
      dividerColor: colors.border,
      extensions: [colors],
      visualDensity:
          compact ? VisualDensity.compact : VisualDensity.standard,
      iconTheme: IconThemeData(
        color: colors.textPrimary,
        size: compact ? 20 : 24,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: colors.textPrimary,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: colors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 12 : 18),
        ),
        margin: EdgeInsets.zero,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(compact ? 14 : 20),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 14 : 20),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      dividerTheme: DividerThemeData(color: colors.border),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return colors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary.withValues(alpha: 0.45);
          }
          return colors.border;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.inputFill,
        isDense: compact,
        contentPadding: EdgeInsets.symmetric(
          horizontal: inputPadH,
          vertical: inputPadV,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: const BorderSide(
            color: AppColors.borderFocused,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        hintStyle: TextStyle(
          color: colors.textHint,
          fontSize: compact ? 13 : 15,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: TextStyle(
          color: colors.textSecondary,
          fontSize: compact ? 12 : 14,
        ),
        errorStyle: TextStyle(
          color: AppColors.error,
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w400,
        ),
        prefixIconColor: colors.textSecondary,
        suffixIconColor: colors.textSecondary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          shadowColor: colors.shadow,
          minimumSize: Size(double.infinity, buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: TextStyle(
            fontSize: compact ? 15 : 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: TextStyle(
            fontSize: compact ? 14 : 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: TextStyle(
            fontSize: compact ? 14 : 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? AppColors.primary : AppColors.primaryDark,
          textStyle: TextStyle(
            fontSize: compact ? 13 : 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: compact,
        minVerticalPadding: compact ? 6 : 10,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall,
        iconColor: colors.textPrimary,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(AppColors.onPrimary),
        side: BorderSide(color: colors.border, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 10 : 14),
        ),
        contentTextStyle: TextStyle(
          fontSize: compact ? 13 : 15,
          fontWeight: FontWeight.w500,
          color: colors.textPrimary,
        ),
      ),
      textTheme: textTheme,
    );
  }
}
