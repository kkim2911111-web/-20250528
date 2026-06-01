import 'package:flutter/material.dart';

/// 단지카 — 토스 스타일 컬러
abstract final class DanjiColors {
  /// 페이지 배경 (토스 그레이)
  static const pageGray = Color(0xFFF2F4F6);
  static const background = pageGray;

  static const skyLight = Color(0xFFE3F2FD);
  static const skySoft = Color(0xFFBBDEFB);
  static const surface = Color(0xFFFFFFFF);

  /// 브랜드 블루
  static const brandBlue = Color(0xFF1A6DFF);
  static const brandBlueDark = Color(0xFF0052CC);
  static const buttonBlue = brandBlue;
  static const primaryBlue = brandBlue;
  static const rentalBlue = brandBlue;
  static const headerBlue = Color(0xFF607D8B);

  static const accentRed = Color(0xFFE53935);
  static const danger = accentRed;

  static const textPrimary = Color(0xFF191F28);
  static const textSecondary = Color(0xFF8B95A1);
  static const textMuted = Color(0xFFB0B8C1);
  static const border = Color(0xFFE5E8EB);

  static const badgeBlue = Color(0xFF42A5F5);
  static const sectionOperating = Color(0xFFFB8C00);
  static const sectionWaiting = brandBlue;
  static const sectionFinished = Color(0xFF66BB6A);
  static const navSelected = brandBlue;
  static const navUnselected = textMuted;

  static const greetingBlue = skyLight;
  static const actionGreen = brandBlue;
  static const returnBrown = brandBlue;
  static const badgeGreen = badgeBlue;
}
