import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';

/// 면허 진위 확인 결과 팝업
abstract final class LicenseVerifyFeedback {
  static const message = '면허증 확인이 완료되었습니다.';

  static Future<void> showSuccess(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: DanjiColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '면허증확인',
          style: TextStyle(
            color: DanjiColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          message,
          style: TextStyle(
            color: DanjiColors.textSecondary,
            height: 1.45,
            fontSize: 15,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: DanjiColors.rentalBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}
