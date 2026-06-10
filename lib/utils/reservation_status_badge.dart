import 'package:flutter/material.dart';

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
        label: '이용완료',
        background: Color(0xFFF2F4F6),
        foreground: Color(0xFF6B7280),
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
