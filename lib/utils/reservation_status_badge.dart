import 'package:flutter/material.dart';

import 'refund_status_display.dart';

/// 예약 status + is_no_show → 한글 배지 (전체 예약·대여 관리 공통)
class ReservationStatusStyle {
  final String label;
  final Color background;
  final Color foreground;

  const ReservationStatusStyle({
    required this.label,
    required this.background,
    required this.foreground,
  });
}

ReservationStatusStyle resolveReservationStatusStyle({
  required String status,
  bool isNoShow = false,
}) {
  final normalized = status.trim().toLowerCase();

  if (isNoShow) {
    return const ReservationStatusStyle(
      label: '노쇼',
      background: Color(0xFFFFF3E0),
      foreground: Color(0xFFE65100),
    );
  }

  switch (normalized) {
    case 'confirmed':
    case 'pending':
      return const ReservationStatusStyle(
        label: '예약확정',
        background: Color(0xFFE8F1FF),
        foreground: Color(0xFF3182F6),
      );
    case 'in_use':
      return const ReservationStatusStyle(
        label: '이용중',
        background: Color(0xFFE8F1FF),
        foreground: Color(0xFF3182F6),
      );
    case 'returned':
      return const ReservationStatusStyle(
        label: '반납완료',
        background: Color(0xFFF2F4F6),
        foreground: Color(0xFF6B7280),
      );
    case 'completed':
      return const ReservationStatusStyle(
        label: '완료',
        background: Color(0xFFDCFCE7),
        foreground: Color(0xFF16A34A),
      );
    case 'cancelled':
      return const ReservationStatusStyle(
        label: '취소',
        background: Color(0xFFFEE2E2),
        foreground: Color(0xFFDC2626),
      );
    default:
      return ReservationStatusStyle(
        label: status.isEmpty ? '—' : status,
        background: const Color(0xFFF2F4F6),
        foreground: const Color(0xFF6B7280),
      );
  }
}

class ReservationStatusBadge extends StatelessWidget {
  final String status;
  final bool isNoShow;

  const ReservationStatusBadge({
    super.key,
    required this.status,
    this.isNoShow = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = resolveReservationStatusStyle(
      status: status,
      isNoShow: isNoShow,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(8),
        border: isNoShow
            ? Border.all(color: const Color(0xFFFF6D00).withValues(alpha: 0.45))
            : null,
      ),
      child: Text(
        style.label,
        style: TextStyle(
          color: style.foreground,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// 상태 + 환불 뱃지 묶음 (표시 전용)
class ReservationDisplayBadgeRow extends StatelessWidget {
  final String status;
  final bool isNoShow;
  final int paidAmount;
  final int refundAmount;

  const ReservationDisplayBadgeRow({
    super.key,
    required this.status,
    this.isNoShow = false,
    this.paidAmount = 0,
    this.refundAmount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final refundKind = refundBadgeKind(
      paidAmount: paidAmount,
      refundAmount: refundAmount,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (refundKind != RefundBadgeKind.none) ...[
          RefundStatusBadge(kind: refundKind),
          const SizedBox(width: 6),
        ],
        ReservationStatusBadge(
          status: status,
          isNoShow: isNoShow,
        ),
      ],
    );
  }
}

/// 반납 지연 중 배지 — in_use + is_overdue
class ReturnOverdueBadge extends StatelessWidget {
  const ReturnOverdueBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFD32F2F).withValues(alpha: 0.45),
        ),
      ),
      child: const Text(
        '반납지연중',
        style: TextStyle(
          color: Color(0xFFC62828),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
