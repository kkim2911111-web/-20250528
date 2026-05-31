import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import 'phone_launcher.dart';

const accidentEmergencyPhone = '010-4455-6676';

Future<void> showAccidentEmergencyDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: DanjiColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '사고신고',
        style: TextStyle(
          color: DanjiColors.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: const Text(
        '사고가 발생하셨나요?\n즉시 긴급 상담원에게 연락하세요.',
        style: TextStyle(
          color: DanjiColors.textSecondary,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('닫기'),
        ),
        FilledButton.icon(
          onPressed: () async {
            final launched = await launchPhoneCall(accidentEmergencyPhone);
            if (!ctx.mounted) return;
            if (!launched) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text('전화 연결: $accidentEmergencyPhone')),
              );
            }
            Navigator.of(ctx).pop();
          },
          icon: const Icon(Icons.phone),
          label: Text('긴급 상담 ($accidentEmergencyPhone)'),
        ),
      ],
    ),
  );
}
