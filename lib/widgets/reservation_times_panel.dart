import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/danji_colors.dart';
import '../utils/reservation_display.dart';
import 'return_confirmation_badge.dart';

enum ReservationTimesLayout { detail, compact }

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
      status: row['status']?.toString(),
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
          if (i > 0) SizedBox(height: layout == ReservationTimesLayout.detail ? 0 : 4),
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
        label: '예약 시간',
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
          label: '대여 시작',
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
          label: '반납',
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
          label: '검수 완료',
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
    if (layout == ReservationTimesLayout.detail) {
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
              child: showReturnConfirmation
                  ? const ReturnConfirmationBadge()
                  : Text(
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

    if (showReturnConfirmation) {
      return Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              height: 1.4,
            ),
          ),
          const ReturnConfirmationBadge(),
        ],
      );
    }

    return Text(
      '$label: $value',
      style: const TextStyle(
        color: DanjiColors.textSecondary,
        height: 1.4,
      ),
    );
  }
}
