import 'package:flutter/material.dart';

import '../services/support_contacts_service.dart';
import '../theme/danji_colors.dart';
import 'phone_launcher.dart';

const _dialogTitle = '일반렌트문의';

const _dialogMessageLine1 = '24시간 이상 대여 시 문의주세요.';
const _dialogMessageLine2 = '운영시간 09:00~18:00';

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

/// 일반 렌트 문의 — 확인 후 전화 연결 (DB `app_support_contacts.rental_inquiry`)
Future<void> showRentalInquiryDialog(BuildContext context) async {
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
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _dialogMessageLine1,
            style: TextStyle(
              color: DanjiColors.textSecondary,
              height: 1.5,
            ),
          ),
          SizedBox(height: 6),
          Text(
            _dialogMessageLine2,
            style: TextStyle(
              color: DanjiColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
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
