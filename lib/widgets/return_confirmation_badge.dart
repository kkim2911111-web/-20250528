import 'package:flutter/material.dart';

/// 대여 시작 후 미반납 — 반납검수·대여 상세 공통
class ReturnConfirmationBadge extends StatelessWidget {
  static const _orange = Color(0xFFF97316);

  const ReturnConfirmationBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _orange.withValues(alpha: 0.45)),
      ),
      child: const Text(
        '반납 확인 필요',
        style: TextStyle(
          color: _orange,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
