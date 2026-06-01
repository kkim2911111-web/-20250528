import 'package:flutter/material.dart';

import 'danji_colors.dart';

/// 토스 스타일 타이포그래피 — 앱 전체 공통
abstract final class DanjiTypography {
  /// 대제목 (화면 이름, 이름)
  static const headline = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: DanjiColors.textPrimary,
    height: 1.3,
    letterSpacing: -0.3,
  );

  static const headlineLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: DanjiColors.textPrimary,
    height: 1.3,
    letterSpacing: -0.3,
  );

  /// 중제목 (카드 차량명, 섹션 제목)
  static const subtitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: DanjiColors.textPrimary,
    height: 1.35,
    letterSpacing: -0.2,
  );

  static const subtitleLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: DanjiColors.textPrimary,
    height: 1.35,
    letterSpacing: -0.2,
  );

  /// 본문 (메뉴명, 일반 텍스트 강조)
  static const body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: DanjiColors.textPrimary,
    height: 1.45,
    letterSpacing: -0.1,
  );

  /// 기본 본문 (앱 기본 텍스트)
  static const bodyRegular = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: DanjiColors.textPrimary,
    height: 1.45,
    letterSpacing: -0.1,
  );

  /// 보조 (날짜, 상태값, 동호수)
  static const secondary = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: DanjiColors.textSecondary,
    height: 1.4,
  );

  static const secondaryMedium = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: DanjiColors.textSecondary,
    height: 1.4,
  );

  /// 캡션 (안내문구, 작은 설명)
  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: DanjiColors.textMuted,
    height: 1.4,
  );

  /// 주요 버튼 (대여하기, 반납하기 등)
  static const buttonPrimary = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  /// 보조 버튼
  static const buttonSecondary = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
  );

  /// Material TextTheme 매핑
  static TextTheme get materialTextTheme => const TextTheme(
        displayLarge: headlineLarge,
        displayMedium: headline,
        displaySmall: headline,
        headlineLarge: headlineLarge,
        headlineMedium: headline,
        headlineSmall: headline,
        titleLarge: subtitleLarge,
        titleMedium: subtitle,
        titleSmall: subtitle,
        bodyLarge: bodyRegular,
        bodyMedium: body,
        bodySmall: secondary,
        labelLarge: buttonPrimary,
        labelMedium: buttonSecondary,
        labelSmall: caption,
      );
}

/// 자주 쓰는 모서리·그림자
abstract final class DanjiRadius {
  static final cardBorder = BorderRadius.circular(16);
  static final buttonBorder = BorderRadius.circular(14);
}

abstract final class DanjiShadow {
  static const soft = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];
}
