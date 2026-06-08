import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/super_admin_models.dart';
import '../theme/danji_colors.dart';

final _won = NumberFormat('#,###');
final _dateTime = DateFormat('yyyy-MM-dd HH:mm');

class SettlementCountRow extends StatelessWidget {
  final int paymentCount;
  final int cancelCount;
  final int rentalCount;
  final String? paymentSublabel;

  const SettlementCountRow({
    super.key,
    required this.paymentCount,
    required this.cancelCount,
    required this.rentalCount,
    this.paymentSublabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CountChip(
            label: '결제건수',
            sublabel: paymentSublabel,
            value: paymentCount,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CountChip(label: '취소건수', value: cancelCount),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CountChip(
            label: '대여건수',
            sublabel: '정산기준',
            value: rentalCount,
          ),
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final String? sublabel;
  final int value;

  const _CountChip({
    required this.label,
    this.sublabel,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: DanjiColors.pageBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sublabel == null ? label : '$label($sublabel)',
            style: const TextStyle(
              color: DanjiColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$value건',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class SettlementAmountRow extends StatelessWidget {
  final String label;
  final int amount;
  final bool muted;
  final bool emphasize;

  const SettlementAmountRow({
    super.key,
    required this.label,
    required this.amount,
    this.muted = false,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = emphasize
        ? DanjiColors.textPrimary
        : (muted ? DanjiColors.textSecondary : DanjiColors.textPrimary);
    final weight = emphasize ? FontWeight.w800 : FontWeight.w600;
    final size = emphasize ? 15.0 : 13.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: size,
                fontWeight: weight,
              ),
            ),
          ),
          Text(
            '₩${_won.format(amount)}',
            style: TextStyle(
              color: color,
              fontSize: size,
              fontWeight: weight,
            ),
          ),
        ],
      ),
    );
  }
}

class SettlementReservationList extends StatelessWidget {
  final List<SuperAdminSettlementReservation> items;
  final int year;
  final int month;

  const SettlementReservationList({
    super.key,
    required this.items,
    required this.year,
    required this.month,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '완료 예약 상세 · $year년 $month월',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text(
                    '해당 월 완료 예약 내역이 없습니다.',
                    style: TextStyle(color: DanjiColors.textSecondary),
                  ),
                )
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final item = items[i];
                    final period =
                        '${item.displayRentalStartAt != null ? _dateTime.format(item.displayRentalStartAt!.toLocal()) : '-'} ~ '
                        '${item.displayRentalEndAt != null ? _dateTime.format(item.displayRentalEndAt!.toLocal()) : '-'}';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        item.reservationNumberLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        '${item.renterName} · $period',
                        style: const TextStyle(fontSize: 13),
                      ),
                      trailing: Text(
                        '₩${_won.format(item.totalPrice)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: DanjiColors.buttonBlue,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

Color settlementBadgeColor({
  required bool isSettled,
  required bool isRequested,
  required Color settledColor,
  required Color requestedColor,
  required Color unsettledColor,
}) {
  if (isSettled) return settledColor;
  if (isRequested) return requestedColor;
  return unsettledColor;
}
