import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.card,
    required this.surface,
    required this.sidebar,
    required this.sidebarSelected,
    required this.sidebarMuted,
    required this.header,
    required this.chip,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.border,
    required this.inputFill,
    required this.shadow,
  });

  // Lime green from the GMS logo — same in both themes
  static const Color primary = Color(0xFFA2D929);
  static const Color primaryDark = Color(0xFF7FB31F);
  static const Color secondary = Color(0xFF8BC34A);
  static const Color headerAccent = Color(0xFFA2D929);
  static const Color borderFocused = primary;
  static const Color error = Color(0xFFDC2626);
  static const Color success = Color(0xFF16A34A);
  static const Color onPrimary = Color(0xFF111827);
  static const Color cropBackdrop = Color(0xFF111827);

  final Color background;
  final Color card;
  final Color surface;
  final Color sidebar;
  final Color sidebarSelected;
  final Color sidebarMuted;
  final Color header;
  final Color chip;
  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;
  final Color border;
  final Color inputFill;
  final Color shadow;

  static const AppColors light = AppColors(
    background: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    sidebar: Color(0xFFF7FBEA),
    sidebarSelected: Color(0xFFD4EFA0),
    sidebarMuted: Color(0xFF3F4A2A),
    header: Color(0xFFE6F3B8),
    chip: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF6B7280),
    textHint: Color(0xFFB0B7C3),
    border: Color(0xFFF0F1F3),
    inputFill: Color(0xFFF4F5F7),
    shadow: Color(0x14000000),
  );

  static const AppColors dark = AppColors(
    background: Color(0xFF12140F),
    card: Color(0xFF1A1D16),
    surface: Color(0xFF1A1D16),
    sidebar: Color(0xFF161910),
    sidebarSelected: Color(0xFF3A4A16),
    sidebarMuted: Color(0xFFB7C49A),
    header: Color(0xFF1E2614),
    chip: Color(0xFF2A3120),
    textPrimary: Color(0xFFF2F5E8),
    textSecondary: Color(0xFFB0B8A0),
    textHint: Color(0xFF7E8670),
    border: Color(0xFF2C3224),
    inputFill: Color(0xFF22261C),
    shadow: Color(0x66000000),
  );

  static AppColors of(BuildContext context) {
    return Theme.of(context).extension<AppColors>() ?? light;
  }

  @override
  AppColors copyWith({
    Color? background,
    Color? card,
    Color? surface,
    Color? sidebar,
    Color? sidebarSelected,
    Color? sidebarMuted,
    Color? header,
    Color? chip,
    Color? textPrimary,
    Color? textSecondary,
    Color? textHint,
    Color? border,
    Color? inputFill,
    Color? shadow,
  }) {
    return AppColors(
      background: background ?? this.background,
      card: card ?? this.card,
      surface: surface ?? this.surface,
      sidebar: sidebar ?? this.sidebar,
      sidebarSelected: sidebarSelected ?? this.sidebarSelected,
      sidebarMuted: sidebarMuted ?? this.sidebarMuted,
      header: header ?? this.header,
      chip: chip ?? this.chip,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textHint: textHint ?? this.textHint,
      border: border ?? this.border,
      inputFill: inputFill ?? this.inputFill,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      sidebarSelected: Color.lerp(sidebarSelected, other.sidebarSelected, t)!,
      sidebarMuted: Color.lerp(sidebarMuted, other.sidebarMuted, t)!,
      header: Color.lerp(header, other.header, t)!,
      chip: Color.lerp(chip, other.chip, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textHint: Color.lerp(textHint, other.textHint, t)!,
      border: Color.lerp(border, other.border, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}
