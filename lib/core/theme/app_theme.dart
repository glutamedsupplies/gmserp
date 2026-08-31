import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

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

    // Inter — clean, modern UI font used across the app.
    TextStyle font({
      required double size,
      required FontWeight weight,
      required Color color,
      double? letterSpacing,
    }) =>
        GoogleFonts.inter(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: letterSpacing,
        );

    final textTheme = TextTheme(
      headlineLarge: font(
        size: compact ? 24 : 30,
        weight: FontWeight.w700,
        color: colors.textPrimary,
        letterSpacing: -0.5,
      ),
      headlineMedium: font(
        size: compact ? 20 : 26,
        weight: FontWeight.w700,
        color: colors.textPrimary,
        letterSpacing: -0.3,
      ),
      headlineSmall: font(
        size: compact ? 18 : 22,
        weight: FontWeight.w700,
        color: colors.textPrimary,
      ),
      titleLarge: font(
        size: compact ? 17 : 21,
        weight: FontWeight.w800,
        color: colors.textPrimary,
      ),
      titleMedium: font(
        size: compact ? 14 : 17,
        weight: FontWeight.w700,
        color: colors.textPrimary,
      ),
      titleSmall: font(
        size: compact ? 13 : 15,
        weight: FontWeight.w700,
        color: colors.textPrimary,
      ),
      bodyLarge: font(
        size: compact ? 14 : 16,
        weight: FontWeight.w400,
        color: colors.textPrimary,
      ),
      bodyMedium: font(
        size: compact ? 13 : 15,
        weight: FontWeight.w400,
        color: colors.textSecondary,
      ),
      bodySmall: font(
        size: compact ? 11 : 13,
        weight: FontWeight.w400,
        color: colors.textSecondary,
      ),
      labelLarge: font(
        size: compact ? 12 : 14,
        weight: FontWeight.w700,
        color: colors.textPrimary,
      ),
      labelMedium: font(
        size: compact ? 11 : 13,
        weight: FontWeight.w600,
        color: colors.textSecondary,
      ),
      labelSmall: font(
        size: compact ? 10 : 12,
        weight: FontWeight.w600,
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
      fontFamily: GoogleFonts.inter().fontFamily,
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
        hintStyle: font(
          size: compact ? 13 : 15,
          weight: FontWeight.w400,
          color: colors.textHint,
        ),
        labelStyle: font(
          size: compact ? 12 : 14,
          weight: FontWeight.w500,
          color: colors.textSecondary,
        ),
        errorStyle: font(
          size: compact ? 11 : 12,
          weight: FontWeight.w400,
          color: AppColors.error,
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
          textStyle: font(
            size: compact ? 15 : 17,
            weight: FontWeight.w600,
            color: AppColors.onPrimary,
            letterSpacing: 0.3,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: font(
            size: compact ? 14 : 16,
            weight: FontWeight.w700,
            color: AppColors.onPrimary,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: font(
            size: compact ? 14 : 16,
            weight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? AppColors.primary : AppColors.primaryDark,
          textStyle: font(
            size: compact ? 13 : 15,
            weight: FontWeight.w600,
            color: isDark ? AppColors.primary : AppColors.primaryDark,
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
        contentTextStyle: font(
          size: compact ? 13 : 15,
          weight: FontWeight.w500,
          color: colors.textPrimary,
        ),
      ),
      textTheme: textTheme,
    );
  }
}
