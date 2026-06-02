import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';

/// 입주민 인증 신청 후 승인 대기 안내
class ResidentVerificationPendingPanel extends StatelessWidget {
  const ResidentVerificationPendingPanel({super.key});

  static const message =
      '주민 인증 절차가 진행 중입니다. 잠시만 기다려 주세요.';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.hourglass_top_rounded,
              size: 48,
              color: DanjiColors.buttonBlue.withValues(alpha: 0.85),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: DanjiColors.textPrimary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '관리자 승인이 완료되면 예약·대여 기능을 이용할 수 있습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DanjiColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
