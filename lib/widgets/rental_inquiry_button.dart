import 'package:flutter/material.dart';

import '../utils/rental_inquiry_flow.dart';

/// 홈 화면 — 일반 렌트 문의 버튼 (카드형)
class RentalInquiryButton extends StatelessWidget {
  const RentalInquiryButton({super.key});

  static const Color _primaryBlue = Color(0xFF3182F6);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showRentalInquiryDialog(context),
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFE8F0FE),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F1FB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.phone_outlined,
                  size: 18,
                  color: _primaryBlue,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '일반 렌트 문의',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF111111),
                        height: 1.25,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '24시간 이상 대여 상담',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF888888),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: _primaryBlue,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '전화 연결',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFFFFFFF),
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
