import 'package:flutter/material.dart';

import '../config/payment_config.dart';

Future<TossPaymentMethod?> showPaymentMethodSheet(BuildContext context) {
  return showModalBottomSheet<TossPaymentMethod>(
    context: context,
    backgroundColor: const Color(0xFF0B2235),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '결제 수단 선택',
                style: TextStyle(
                  color: Color(0xFFEAF2FF),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (PaymentConfig.isTestKey) ...[
                const SizedBox(height: 6),
                const Text(
                  '테스트 모드 — 실제 결제되지 않습니다',
                  style: TextStyle(color: Color(0xFF9AB3C9), fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              for (final method in TossPaymentMethod.values)
                ListTile(
                  leading: Icon(_iconFor(method), color: const Color(0xFFEAF2FF)),
                  title: Text(
                    method.label,
                    style: const TextStyle(color: Color(0xFFEAF2FF)),
                  ),
                  onTap: () => Navigator.pop(context, method),
                ),
            ],
          ),
        ),
      );
    },
  );
}

IconData _iconFor(TossPaymentMethod method) {
  switch (method) {
    case TossPaymentMethod.card:
      return Icons.credit_card;
    case TossPaymentMethod.transfer:
      return Icons.account_balance;
    case TossPaymentMethod.kakaoPay:
      return Icons.chat_bubble;
  }
}
