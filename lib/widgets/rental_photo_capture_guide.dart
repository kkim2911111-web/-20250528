import 'package:flutter/material.dart';

import '../services/rental_start_service.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';

/// 차량 사진 촬영 — 슬롯별 안내 + N/5 진행 표시
class RentalPhotoCaptureGuide extends StatelessWidget {
  final int capturedCount;
  final bool locked;

  const RentalPhotoCaptureGuide({
    super.key,
    required this.capturedCount,
    this.locked = false,
  });

  static final int _guideTotal = RentalStartService.guidedPhotoLabels.length;

  @override
  Widget build(BuildContext context) {
    if (locked) return const SizedBox.shrink();

    final nextIndex = capturedCount.clamp(0, _guideTotal - 1);
    final label = RentalStartService.guidedPhotoLabels[nextIndex];
    final progress = capturedCount >= _guideTotal
        ? _guideTotal
        : (capturedCount + 1).clamp(1, _guideTotal);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: DanjiColors.skyLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DanjiColors.buttonBlue.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              capturedCount >= _guideTotal
                  ? '계기판을 촬영해주세요'
                  : '$label을 촬영해주세요',
              style: DanjiTypography.subtitle.copyWith(
                color: DanjiColors.buttonBlue,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: DanjiColors.buttonBlue,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              capturedCount >= _guideTotal
                  ? '${capturedCount + 1}/6'
                  : '$progress/$_guideTotal',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
