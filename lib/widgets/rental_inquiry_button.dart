import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import '../utils/rental_inquiry_flow.dart';

/// 홈 화면 — 일반 렌트 문의 버튼
class RentalInquiryButton extends StatelessWidget {
  const RentalInquiryButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: () => showRentalInquiryDialog(context),
        icon: const Icon(Icons.phone_in_talk_outlined, size: 20),
        label: const Text(
          '일반 렌트 문의',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: DanjiColors.primaryBlue,
          side: const BorderSide(color: DanjiColors.skySoft),
          backgroundColor: DanjiColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
