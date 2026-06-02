import 'package:flutter/material.dart';

/// 단지카 — 슬레이트 블루 + 톤다운 레드 팔레트
abstract final class DanjiColors {
  static const slateBlue = Color(0xFF3182F6);
  static const toneRed = Color(0xFFF04452);

  /// 레거시 별칭 (차콜/살몬 참조 → 슬레이트/레드)
  static const charcoal = slateBlue;
  static const salmon = toneRed;

  static const brandBlue = slateBlue;
  static const brandBlueShadow = Color(0xFF1A5FCC);
  static const brandBlueDark = Color(0xFF1A5FCC);
  static const buttonBlue = slateBlue;
  static const primaryBlue = slateBlue;
  static const rentalBlue = slateBlue;
  static const headerBlue = slateBlue;

  static const accentRed = toneRed;
  static const danger = toneRed;
  static const dangerBright = toneRed;
  static const dangerBrightDark = Color(0xFFC02030);

  /// 페이지 배경
  static const pageBackground = Color(0xFFF2F4F6);
  static const background = pageBackground;
  static const pageGray = pageBackground;

  static const surface = Color(0xFFFFFFFF);
  static const skyLight = Color(0xFFEBF3FF);
  static const skySoft = Color(0xFFEBF3FF);

  /// 홈 문열림/문닫힘 아웃라인 버튼
  static const doorUnlockBg = Color(0xFFEBF3FF);
  static const doorUnlockFg = Color(0xFF1A5FCC);
  static const doorUnlockBorder = slateBlue;

  static const doorLockBg = Color(0xFFFFF0F0);
  static const doorLockFg = Color(0xFFC02030);
  static const doorLockBorder = toneRed;

  /// 이벤트 배너
  static const bannerBackground = Color(0xFFEBF3FF);
  static const bannerText = Color(0xFF1B3A6B);
  static const bannerTextMuted = Color(0x991B3A6B);

  /// 상태 태그
  static const tagRentingBg = Color(0xFFFFF0F0);
  static const tagRentingText = toneRed;
  static const tagConfirmedBg = Color(0xFFEFEFEF);
  static const tagConfirmedText = Color(0xFF1B3A6B);

  static const toastBackground = Color(0xFF323232);
  static const cardShadow = Color(0x12000000);

  static const textPrimary = Color(0xFF191F28);
  static const textSecondary = Color(0xFF8B95A1);
  static const textMuted = Color(0xFFB0B8C1);
  static const border = Color(0xFFE5E8EB);

  static const badgeBlue = slateBlue;
  static const sectionOperating = toneRed;
  static const sectionWaiting = slateBlue;
  static const sectionFinished = slateBlue;
  static const navSelected = slateBlue;
  static const navUnselected = textMuted;

  static const greetingBlue = skyLight;
  static const actionGreen = slateBlue;
  static const returnBrown = slateBlue;
  static const badgeGreen = slateBlue;
}
