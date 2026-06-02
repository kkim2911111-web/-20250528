import 'package:flutter/material.dart';

import 'danji_colors.dart';
import 'danji_typography.dart';

/// 단지카 공통 라이트 테마 — 토스 스타일 타이포그래피
abstract final class DanjiTheme {
  static ThemeData get light {
    final textTheme = DanjiTypography.materialTextTheme;

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
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: DanjiColors.background,
        foregroundColor: DanjiColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: DanjiTypography.subtitleLarge.copyWith(
          fontWeight: FontWeight.w700,
        ),
        toolbarTextStyle: DanjiTypography.body,
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
        hintStyle: DanjiTypography.secondary.copyWith(
          color: DanjiColors.textMuted,
        ),
        labelStyle: DanjiTypography.secondary,
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
          textStyle: DanjiTypography.buttonPrimary.copyWith(
            color: Colors.white,
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
          textStyle: DanjiTypography.buttonSecondary.copyWith(
            color: DanjiColors.buttonBlue,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DanjiColors.buttonBlue,
          textStyle: DanjiTypography.buttonSecondary.copyWith(
            color: DanjiColors.buttonBlue,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: DanjiColors.surface,
        indicatorColor: DanjiColors.brandBlue.withValues(alpha: 0.1),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return DanjiTypography.caption.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected
                ? DanjiColors.navSelected
                : DanjiColors.navUnselected,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: DanjiColors.toastBackground,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.35,
        ),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        actionTextColor: Colors.white,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: DanjiColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: DanjiTypography.subtitleLarge.copyWith(
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: DanjiTypography.bodyRegular.copyWith(
          color: DanjiColors.textSecondary,
          height: 1.5,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: DanjiColors.buttonBlue,
      ),
      listTileTheme: ListTileThemeData(
        tileColor: DanjiColors.surface,
        selectedTileColor: DanjiColors.skyLight,
        iconColor: DanjiColors.buttonBlue,
        textColor: DanjiColors.textPrimary,
        titleTextStyle: DanjiTypography.body,
        subtitleTextStyle: DanjiTypography.secondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }

  static ButtonStyle get primaryButton => FilledButton.styleFrom(
        backgroundColor: DanjiColors.buttonBlue,
        foregroundColor: Colors.white,
        textStyle: DanjiTypography.buttonPrimary.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      );

  static ButtonStyle get dangerButton => FilledButton.styleFrom(
        backgroundColor: DanjiColors.accentRed,
        foregroundColor: Colors.white,
        textStyle: DanjiTypography.buttonPrimary.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      );
}
