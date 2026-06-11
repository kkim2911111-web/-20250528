import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/danji_colors.dart';
import '../utils/reservation_display.dart';
import 'return_confirmation_badge.dart';

enum ReservationTimesLayout { detail, compact }

/// 반납 검수·상세 공통 시간 라벨 (4종 고정 폭)
const reservationTimesLabelWidth = 76.0;
const reservationScheduledTimeLabel = '예약 시간';
const reservationRentalStartLabel = '대여 시작';
const reservationReturnTimeLabel = '반납 시간';
const reservationInspectionDoneLabel = '검수 완료';

class ReservationTimesPanel extends StatelessWidget {
  final DateFormat formatter;
  final ReservationTimesMode mode;
  final ReservationTimesLayout layout;
  final DateTime? scheduledStartAt;
  final DateTime? scheduledEndAt;
  final DateTime? rentalStartedAt;
  final DateTime? returnedAt;
  final DateTime? returnCompletedAt;
  final bool isNoShow;
  final String? status;

  const ReservationTimesPanel({
    super.key,
    required this.formatter,
    required this.mode,
    this.layout = ReservationTimesLayout.compact,
    this.scheduledStartAt,
    this.scheduledEndAt,
    this.rentalStartedAt,
    this.returnedAt,
    this.returnCompletedAt,
    this.isNoShow = false,
    this.status,
  });

  factory ReservationTimesPanel.fromMap({
    required Map<String, dynamic> row,
    required DateFormat formatter,
    required ReservationTimesMode mode,
    ReservationTimesLayout layout = ReservationTimesLayout.compact,
  }) {
    final status = row['status']?.toString();
    return ReservationTimesPanel(
      formatter: formatter,
      mode: mode,
      layout: layout,
      scheduledStartAt: scheduledStartFromMap(row),
      scheduledEndAt: scheduledEndFromMap(row),
      rentalStartedAt: parseReservationDate(row['rental_started_at']),
      returnedAt: parseReservationDate(row['returned_at']),
      returnCompletedAt: resolveReturnCompletedAt(
        status: status,
        returnCompletedAt: parseReservationDate(row['return_completed_at']),
        updatedAt: parseReservationDate(row['updated_at']),
      ),
      isNoShow: row['is_no_show'] == true,
      status: status,
    );
  }

  bool get _needsReturnConfirmation {
    if (isNoShow || rentalStartedAt == null || returnedAt != null) {
      return false;
    }
    final normalized = status?.trim().toLowerCase();
    if (normalized == 'in_use') return true;
    return mode == ReservationTimesMode.inspectionPending;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows();
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          _TimeRow(
            label: rows[i].label,
            value: rows[i].value,
            layout: layout,
            showReturnConfirmation: rows[i].showReturnConfirmation,
          ),
        ],
      ],
    );
  }

  List<_TimeRowData> _buildRows() {
    final rows = <_TimeRowData>[
      _TimeRowData(
        label: reservationScheduledTimeLabel,
        value: formatScheduledPeriod(
          formatter: formatter,
          startAt: scheduledStartAt,
          endAt: scheduledEndAt,
        ),
      ),
    ];

    final showRentalStart = _shouldShowOptional(rentalStartedAt);
    final showReturned = _shouldShowOptional(returnedAt);
    final forceShowActual = mode == ReservationTimesMode.inspectionPending ||
        mode == ReservationTimesMode.inspectionCompleted;

    if (showRentalStart || forceShowActual) {
      rows.add(
        _TimeRowData(
          label: reservationRentalStartLabel,
          value: _formatActualTime(
            timestamp: rentalStartedAt,
            forceShow: forceShowActual,
          ),
        ),
      );
    }

    if (showReturned || forceShowActual) {
      rows.add(
        _TimeRowData(
          label: reservationReturnTimeLabel,
          value: _needsReturnConfirmation
              ? ''
              : _formatActualTime(
                  timestamp: returnedAt,
                  forceShow: forceShowActual,
                ),
          showReturnConfirmation: _needsReturnConfirmation,
        ),
      );
    }

    if (mode == ReservationTimesMode.inspectionCompleted) {
      rows.add(
        _TimeRowData(
          label: reservationInspectionDoneLabel,
          value: formatOptionalDateTime(formatter, returnCompletedAt),
        ),
      );
    }

    return rows;
  }

  bool _shouldShowOptional(DateTime? value) {
    if (value == null) return false;
    return mode == ReservationTimesMode.residentDetail ||
        mode == ReservationTimesMode.admin;
  }

  String _formatActualTime({
    required DateTime? timestamp,
    required bool forceShow,
  }) {
    if (isNoShow && forceShow) return '미대여';
    if (timestamp != null) return formatOptionalDateTime(formatter, timestamp);
    if (forceShow) return '-';
    return '-';
  }
}

class _TimeRowData {
  final String label;
  final String value;
  final bool showReturnConfirmation;

  const _TimeRowData({
    required this.label,
    required this.value,
    this.showReturnConfirmation = false,
  });
}

class _TimeRow extends StatelessWidget {
  final String label;
  final String value;
  final ReservationTimesLayout layout;
  final bool showReturnConfirmation;

  const _TimeRow({
    required this.label,
    required this.value,
    required this.layout,
    this.showReturnConfirmation = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      color: DanjiColors.textSecondary,
      fontSize: layout == ReservationTimesLayout.detail ? 14 : 13,
      height: 1.4,
    );
    final valueStyle = TextStyle(
      color: DanjiColors.textPrimary,
      fontSize: layout == ReservationTimesLayout.detail ? 14 : 13,
      fontWeight: layout == ReservationTimesLayout.detail
          ? FontWeight.w600
          : FontWeight.w500,
      height: 1.4,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: reservationTimesLabelWidth,
          child: Text(label, style: labelStyle),
        ),
        Expanded(
          child: showReturnConfirmation
              ? const ReturnConfirmationBadge()
              : Text(value, style: valueStyle),
        ),
      ],
    );
  }
}
