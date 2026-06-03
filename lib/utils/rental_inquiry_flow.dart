import 'package:flutter/material.dart';

import '../services/support_contacts_service.dart';
import '../theme/danji_colors.dart';
import 'phone_launcher.dart';

const _dialogTitle = '1일 이상은 일반렌트로 문의해주세요';

const _dialogMessage =
    '장기 대여는 일반렌트 상담을 통해 더 합리적으로 이용하실 수 있습니다.';

/// 일반렌트 문의 — `rental_inquiry` 번호로 전화 연결
Future<void> launchRentalInquiryPhone(BuildContext context) async {
  final phone = await SupportContactsService().fetchRentalInquiryPhone();
  if (!context.mounted) return;

  if (phone == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '일반렌트 문의 전화번호가 등록되지 않았습니다. 관리자에게 문의해주세요.',
        ),
      ),
    );
    return;
  }

  final launched = await launchPhoneCall(phone);
  if (!context.mounted) return;
  if (!launched) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('전화 연결: $phone')),
    );
  }
}

/// 일반 렌트 문의 — 확인 후 전화 연결 (DB `app_support_contacts.emergency_phone`)
Future<void> showRentalInquiryDialog(BuildContext context) async {
  final phone = await SupportContactsService().fetchEmergencyPhone();
  if (!context.mounted) return;

  if (phone == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('긴급 상담 번호가 등록되지 않았습니다. 관리자에게 문의해주세요.'),
      ),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: DanjiColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        _dialogTitle,
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
            Navigator.of(ctx).pop();
            final launched = await launchPhoneCall(phone);
            if (!context.mounted) return;
            if (!launched) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('전화 연결: $phone')),
              );
            }
          },
          style: FilledButton.styleFrom(
            backgroundColor: DanjiColors.primaryBlue,
            foregroundColor: Colors.white,
          ),
          child: const Text('전화 문의'),
        ),
      ],
    ),
  );
}
