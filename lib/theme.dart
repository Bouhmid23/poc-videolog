import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

//
// Flutter has a color profile issue so colors will look different
// on Apple devices.
// https://github.com/flutter/flutter/issues/55092
// https://github.com/flutter/flutter/issues/39113
//

extension LKColors on Colors {
  static const primary = Color(0xFF5A8BFF);
  static const primaryDark = Color(0xFF3D6EE0);
  static const secondary = Color(0xFF22D3EE);

  // Surfaces
  static const background = Color(0xFF0B1120);
  static const surface = Color(0xFF111827);
  static const surfaceElevated = Color(0xFF172034);
  static const border = Color(0xFF273449);

  // Text
  static const textPrimary = Color(0xFFF8FAFC);
  static const textSecondary = Color(0xFFB8C4D9);
  static const textHint = Color(0xFF93A2BE);

  // States
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);

  // Backward compatibility in existing code
  static const lkBlue = primary;
  static const lkDarkBlue = surfaceElevated;
}

class LiveKitTheme {
  const LiveKitTheme();

  ThemeData buildThemeData(BuildContext ctx) {
    final baseTextTheme = GoogleFonts.montserratTextTheme(Theme
        .of(ctx)
        .textTheme).apply(
      displayColor: LKColors.textPrimary,
      bodyColor: LKColors.textPrimary,
      decorationColor: LKColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: LKColors.background,
      canvasColor: LKColors.background,
      cardColor: LKColors.surface,
      dividerColor: LKColors.border,
      hintColor: LKColors.textHint,
      iconTheme: const IconThemeData(color: LKColors.textPrimary),
      textTheme: baseTextTheme,

      colorScheme: const ColorScheme.dark(
        primary: LKColors.primary,
        onPrimary: Colors.white,
        secondary: LKColors.secondary,
        onSecondary: Colors.white,
        surface: LKColors.surface,
        onSurface: LKColors.textPrimary,
        error: LKColors.danger,
        onError: Colors.white,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: LKColors.surface,
        foregroundColor: LKColors.textPrimary,
        elevation: 0,
        titleTextStyle: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: LKColors.textPrimary,
        ),
      ),

      cardTheme: CardThemeData(
        color: LKColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: LKColors.border),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStateProperty.all(
            baseTextTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return LKColors.primary.withValues(alpha: 0.45);
            }
            if (states.contains(WidgetState.pressed)) {
              return LKColors.primaryDark;
            }
            return LKColors.primary;
          }),
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        checkColor: WidgetStateProperty.all(Colors.white),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return LKColors.primary;
          return Colors.transparent;
        }),
        side: const BorderSide(color: LKColors.border),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return LKColors.primary;
          return LKColors.border;
        }),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return LKColors.textSecondary;
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: LKColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LKColors.surface,
        labelStyle: const TextStyle(color: LKColors.textSecondary),
        hintStyle: const TextStyle(color: LKColors.textHint),
        prefixIconColor: LKColors.textSecondary,
        suffixIconColor: LKColors.textSecondary,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LKColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LKColors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LKColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LKColors.danger, width: 1.4),
        ),
      ),
    );
  }
}