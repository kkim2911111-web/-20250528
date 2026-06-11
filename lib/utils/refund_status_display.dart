import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';

/// 부분환불 · 전액환불 뱃지 분류 (표시 전용, 환불액 재계산 없음)
enum RefundBadgeKind { none, partial, full }

RefundBadgeKind refundBadgeKind({
  required int paidAmount,
  required int refundAmount,
}) {
  if (refundAmount <= 0 || paidAmount <= 0) return RefundBadgeKind.none;
  if (refundAmount >= paidAmount) return RefundBadgeKind.full;
  return RefundBadgeKind.partial;
}

class RefundStatusBadge extends StatelessWidget {
  final RefundBadgeKind kind;

  const RefundStatusBadge({super.key, required this.kind});

  factory RefundStatusBadge.forAmounts({
    required int paidAmount,
    required int refundAmount,
  }) {
    return RefundStatusBadge(
      kind: refundBadgeKind(
        paidAmount: paidAmount,
        refundAmount: refundAmount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (kind) {
      RefundBadgeKind.partial => '부분환불',
      RefundBadgeKind.full => '전액환불',
      RefundBadgeKind.none => null,
    };
    if (label == null) return const SizedBox.shrink();

    final (foreground, background, border) = switch (kind) {
      RefundBadgeKind.partial => (
        const Color(0xFFD97706),
        const Color(0xFFFEF3C7),
        const Color(0xFFFCD34D),
      ),
      RefundBadgeKind.full => (
        DanjiColors.textSecondary,
        const Color(0xFFF3F4F6),
        DanjiColors.border,
      ),
      RefundBadgeKind.none => (
        DanjiColors.textMuted,
        Colors.transparent,
        Colors.transparent,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
