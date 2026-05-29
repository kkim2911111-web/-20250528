import 'package:flutter/material.dart';

/// 단지카 — 흰/연하늘 배경 · 그레이 글씨 · 파랑 버튼
abstract final class DanjiColors {
  static const background = Color(0xFFF0F7FF);
  static const skyLight = Color(0xFFE3F2FD);
  static const skySoft = Color(0xFFBBDEFB);
  static const surface = Color(0xFFFFFFFF);

  /// 스마트키·대여·예약·운행 등 주요 버튼
  static const buttonBlue = Color(0xFF1E88E5);
  static const primaryBlue = buttonBlue;
  static const rentalBlue = buttonBlue;
  static const headerBlue = Color(0xFF607D8B);

  static const accentRed = Color(0xFFE53935);
  static const danger = accentRed;

  static const textPrimary = Color(0xFF607D8B);
  static const textSecondary = Color(0xFF78909C);
  static const textMuted = Color(0xFF90A4AE);
  static const border = Color(0xFFD6E4F0);

  static const badgeBlue = Color(0xFF42A5F5);
  static const sectionOperating = Color(0xFFFB8C00);
  static const sectionWaiting = buttonBlue;
  static const sectionFinished = Color(0xFF66BB6A);
  static const navSelected = buttonBlue;
  static const navUnselected = textSecondary;

  static const greetingBlue = skyLight;
  static const actionGreen = buttonBlue;
  static const returnBrown = buttonBlue;
  static const badgeGreen = badgeBlue;
}
