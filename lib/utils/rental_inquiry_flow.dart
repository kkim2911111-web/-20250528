import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import 'phone_launcher.dart';

/// 일반 렌트(24시간 이상) 문의 담당자 연락처
const rentalInquiryPhone = '010-4455-6676';

const _dialogMessage =
    '24시간(1일) 이상 대여 시에만 문의 부탁드립니다. 담당자에게 연결하시겠습니까?';

/// 일반 렌트 문의 — 확인 후 전화 연결
Future<void> showRentalInquiryDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: DanjiColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '일반 렌트 문의',
        style: TextStyle(
          color: DanjiColors.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: const Text(
        _dialogMessage,
        style: TextStyle(
          color: DanjiColors.textSecondary,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () async {
            final launched = await launchPhoneCall(rentalInquiryPhone);
            if (!ctx.mounted) return;
            if (!launched) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text('전화 연결: $rentalInquiryPhone')),
              );
            }
            Navigator.of(ctx).pop();
          },
          style: FilledButton.styleFrom(
            backgroundColor: DanjiColors.primaryBlue,
            foregroundColor: Colors.white,
          ),
          child: const Text('전화하기'),
        ),
      ],
    ),
  );
}
