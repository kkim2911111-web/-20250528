import 'package:flutter/material.dart';

/// 하단 토스트 — 다크 그레이, 하단 슬라이드 업
abstract final class DanjiSnackBar {
  static const _background = Color(0xFF323232);

  static SnackBar build(String message) {
    return SnackBar(
      content: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.35,
        ),
      ),
      backgroundColor: _background,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      duration: const Duration(seconds: 3),
    );
  }

  static void show(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(build(message));
  }
}
