import 'package:flutter/material.dart';

import 'danji_colors.dart';

/// 단지카 공통 라이트 테마 — 흰/연하늘 배경 · 그레이 글씨 · 파랑 버튼
abstract final class DanjiTheme {
  static ThemeData get light {
    const textTheme = TextTheme(
      bodyLarge: TextStyle(color: DanjiColors.textPrimary),
      bodyMedium: TextStyle(color: DanjiColors.textPrimary),
      bodySmall: TextStyle(color: DanjiColors.textSecondary),
      titleLarge: TextStyle(
        color: DanjiColors.textPrimary,
        fontWeight: FontWeight.w800,
      ),
      titleMedium: TextStyle(
        color: DanjiColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      labelLarge: TextStyle(color: DanjiColors.textSecondary),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: DanjiColors.background,
      colorScheme: ColorScheme.light(
        primary: DanjiColors.buttonBlue,
        onPrimary: Colors.white,
        secondary: DanjiColors.skySoft,
        surface: DanjiColors.surface,
        onSurface: DanjiColors.textPrimary,
        error: DanjiColors.accentRed,
        outline: DanjiColors.border,
      ),
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: DanjiColors.background,
        foregroundColor: DanjiColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: DanjiColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: DanjiColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: DanjiColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: DanjiColors.border),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DanjiColors.skyLight,
        hintStyle: const TextStyle(color: DanjiColors.textMuted),
        labelStyle: const TextStyle(color: DanjiColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DanjiColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DanjiColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DanjiColors.buttonBlue, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: DanjiColors.buttonBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: DanjiColors.border,
          disabledForegroundColor: DanjiColors.textMuted,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DanjiColors.buttonBlue,
          side: const BorderSide(color: DanjiColors.buttonBlue),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DanjiColors.buttonBlue,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: DanjiColors.surface,
        indicatorColor: DanjiColors.buttonBlue.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected
                ? DanjiColors.buttonBlue
                : DanjiColors.textSecondary,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: DanjiColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: const TextStyle(
          color: DanjiColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: const TextStyle(
          color: DanjiColors.textSecondary,
          height: 1.5,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: DanjiColors.buttonBlue,
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: DanjiColors.surface,
        selectedTileColor: DanjiColors.skyLight,
        iconColor: DanjiColors.buttonBlue,
        textColor: DanjiColors.textPrimary,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }

  static ButtonStyle get primaryButton => FilledButton.styleFrom(
        backgroundColor: DanjiColors.buttonBlue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      );

  static ButtonStyle get dangerButton => FilledButton.styleFrom(
        backgroundColor: DanjiColors.accentRed,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      );
}
