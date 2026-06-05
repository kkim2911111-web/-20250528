import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';

/// 좌우 화살표로 월을 이동하는 필터 바 (포인트 내역·매출 관리 공통)
class MonthFilterBar extends StatelessWidget {
  final String label;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  const MonthFilterBar({
    super.key,
    required this.label,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DanjiColors.border),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
            color: DanjiColors.buttonBlue,
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: DanjiTypography.subtitle.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
            color: canGoNext ? DanjiColors.buttonBlue : DanjiColors.textMuted,
          ),
        ],
      ),
    );
  }
}
