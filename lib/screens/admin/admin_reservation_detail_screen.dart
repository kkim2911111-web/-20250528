import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/admin_timeline.dart';
import '../../theme/danji_colors.dart';
import '../../utils/reservation_display.dart';
import '../../utils/reservation_status_badge.dart';
import '../../widgets/danji_app_bar.dart';
import '../../widgets/reservation_times_panel.dart';

/// 관리자 — 타임라인·목록 공통 예약 상세
class AdminReservationDetailScreen extends StatelessWidget {
  final AdminTimelineReservation reservation;

  const AdminReservationDetailScreen({
    super.key,
    required this.reservation,
  });

  @override
  Widget build(BuildContext context) {
    final won = NumberFormat('#,###');
    final dateTime = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      backgroundColor: DanjiColors.background,
      appBar: const DanjiAppBar(title: '예약 상세', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  reservation.vehicleName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: DanjiColors.textPrimary,
                  ),
                ),
              ),
              ReservationStatusBadge(
                status: reservation.isNoShow ? 'completed' : reservation.status,
                isNoShow: reservation.isNoShow,
              ),
            ],
          ),
          if (reservation.carNumber != null &&
              reservation.carNumber!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              reservation.carNumber!,
              style: const TextStyle(color: DanjiColors.textSecondary),
            ),
          ],
          const SizedBox(height: 20),
          _InfoRow(label: '예약번호', value: reservation.reservationNumberLabel),
          _InfoRow(label: '임차인', value: reservation.renterName),
          _InfoRow(
            label: '연락처',
            value: reservation.renterPhone == '미등록'
                ? '미등록'
                : reservation.renterPhone,
          ),
          ReservationTimesPanel(
            formatter: dateTime,
            mode: ReservationTimesMode.admin,
            layout: ReservationTimesLayout.detail,
            scheduledStartAt: reservation.startAt,
            scheduledEndAt: reservation.endAt,
            rentalStartedAt: reservation.rentalStartedAt,
            returnedAt: reservation.returnedAt,
          ),
          _InfoRow(
            label: '결제 금액',
            value: '₩${won.format(reservation.totalPrice)}',
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: DanjiColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: DanjiColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
