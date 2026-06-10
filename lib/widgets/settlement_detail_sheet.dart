import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/rental_detail.dart';
import '../models/super_admin_models.dart';
import '../theme/danji_colors.dart';
import 'rental_type_badge.dart';

typedef RentalDetailItemTap = void Function(
  String reservationId, {
  RentalDetailPrefetch? prefetch,
});

final _won = NumberFormat('#,###');
final _dateTime = DateFormat('yyyy-MM-dd HH:mm');

enum SettlementDetailTab { rental, payment, cancel }

extension SettlementDetailTabX on SettlementDetailTab {
  String title(int year, int month) {
    switch (this) {
      case SettlementDetailTab.rental:
        return '완료 예약 상세 · $year년 $month월';
      case SettlementDetailTab.payment:
        return '결제 내역 · $year년 $month월';
      case SettlementDetailTab.cancel:
        return '취소 내역 · $year년 $month월';
    }
  }

  String emptyMessage() {
    switch (this) {
      case SettlementDetailTab.rental:
        return '해당 월 완료 예약 내역이 없습니다.';
      case SettlementDetailTab.payment:
        return '해당 월 결제 내역이 없습니다.';
      case SettlementDetailTab.cancel:
        return '해당 월 취소 내역이 없습니다.';
    }
  }
}

class SettlementCountRow extends StatelessWidget {
  final int paymentCount;
  final int cancelCount;
  final int rentalCount;
  final SettlementDetailTab selectedTab;
  final ValueChanged<SettlementDetailTab> onTabSelected;

  const SettlementCountRow({
    super.key,
    required this.paymentCount,
    required this.cancelCount,
    required this.rentalCount,
    required this.selectedTab,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CountChip(
            label: '결제건수',
            sublabel: '결제일',
            value: paymentCount,
            selected: selectedTab == SettlementDetailTab.payment,
            onTap: () => onTabSelected(SettlementDetailTab.payment),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CountChip(
            label: '취소건수',
            value: cancelCount,
            selected: selectedTab == SettlementDetailTab.cancel,
            onTap: () => onTabSelected(SettlementDetailTab.cancel),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CountChip(
            label: '대여건수',
            sublabel: '정산기준',
            value: rentalCount,
            selected: selectedTab == SettlementDetailTab.rental,
            onTap: () => onTabSelected(SettlementDetailTab.rental),
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
  final bool selected;
  final VoidCallback onTap;

  const _CountChip({
    required this.label,
    this.sublabel,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
        selected ? DanjiColors.buttonBlue : DanjiColors.border;
    final background =
        selected ? const Color(0xFFEFF6FF) : DanjiColors.pageBackground;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sublabel == null ? label : '$label($sublabel)',
                style: TextStyle(
                  color: selected
                      ? DanjiColors.buttonBlue
                      : DanjiColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$value건',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: selected
                      ? DanjiColors.buttonBlue
                      : DanjiColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
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

class SettlementDetailList extends StatelessWidget {
  final SuperAdminSettlementSheet sheet;
  final SettlementDetailTab tab;
  final int year;
  final int month;
  final RentalDetailItemTap? onItemTap;

  const SettlementDetailList({
    super.key,
    required this.sheet,
    required this.tab,
    required this.year,
    required this.month,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tab.title(year, month),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: switch (tab) {
            SettlementDetailTab.rental => _RentalList(
                items: sheet.items,
                emptyMessage: tab.emptyMessage(),
                onItemTap: onItemTap,
              ),
            SettlementDetailTab.payment => _PaymentList(
                items: sheet.paymentItems,
                emptyMessage: tab.emptyMessage(),
                onItemTap: onItemTap,
              ),
            SettlementDetailTab.cancel => _CancelList(
                items: sheet.cancelItems,
                emptyMessage: tab.emptyMessage(),
                onItemTap: onItemTap,
              ),
          },
        ),
      ],
    );
  }
}

@Deprecated('Use SettlementDetailList')
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
    return SettlementDetailList(
      sheet: SuperAdminSettlementSheet(items: items),
      tab: SettlementDetailTab.rental,
      year: year,
      month: month,
    );
  }
}

class _RentalList extends StatelessWidget {
  final List<SuperAdminSettlementReservation> items;
  final String emptyMessage;
  final RentalDetailItemTap? onItemTap;

  const _RentalList({
    required this.items,
    required this.emptyMessage,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: const TextStyle(color: DanjiColors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final item = items[i];
        final period =
            '${item.displayRentalStartAt != null ? _dateTime.format(item.displayRentalStartAt!.toLocal()) : '-'} ~ '
            '${item.displayRentalEndAt != null ? _dateTime.format(item.displayRentalEndAt!.toLocal()) : '-'}';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: onItemTap == null
              ? null
              : () => onItemTap!(item.reservationId),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  item.reservationNumberLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              RentalTypeBadge(rentalType: item.rentalType),
            ],
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
    );
  }
}

class _PaymentList extends StatelessWidget {
  final List<SuperAdminSettlementPaymentItem> items;
  final String emptyMessage;
  final RentalDetailItemTap? onItemTap;

  const _PaymentList({
    required this.items,
    required this.emptyMessage,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: const TextStyle(color: DanjiColors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final item = items[i];
        final paidAt = item.paidAt != null
            ? _dateTime.format(item.paidAt!.toLocal())
            : '-';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: onItemTap == null
              ? null
              : () => onItemTap!(item.reservationId),
          title: Text(
            item.reservationNumberLabel,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            '${item.renterName} · $paidAt',
            style: const TextStyle(fontSize: 13),
          ),
          trailing: Text(
            '₩${_won.format(item.paymentAmount)}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: DanjiColors.buttonBlue,
            ),
          ),
        );
      },
    );
  }
}

class _CancelList extends StatelessWidget {
  final List<SuperAdminSettlementCancelItem> items;
  final String emptyMessage;
  final RentalDetailItemTap? onItemTap;

  const _CancelList({
    required this.items,
    required this.emptyMessage,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: const TextStyle(color: DanjiColors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final item = items[i];
        final cancelledAt = item.cancelledAt != null
            ? _dateTime.format(item.cancelledAt!.toLocal())
            : '-';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: onItemTap == null
              ? null
              : () => onItemTap!(
                    item.reservationId,
                    prefetch: RentalDetailPrefetch(
                      cancelReason: item.cancelReason,
                      paidAmount: item.paidAmount,
                      refundAmount: item.refundAmount,
                    ),
                  ),
          title: Text(
            item.reservationNumberLabel,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            '${item.renterName} · $cancelledAt\n'
            '결제 ₩${_won.format(item.paidAmount)} · '
            '환불 ₩${_won.format(item.refundAmount)} · '
            '${item.cancelReason}',
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
          isThreeLine: true,
        );
      },
    );
  }
}

const settlementNoRevenueBackground = Color(0xFFF3F4F6);
const settlementNoRevenueForeground = Color(0xFF9CA3AF);

bool settlementIsNoRevenue({
  required bool isSettled,
  required bool isRequested,
  required int revenueAmount,
}) =>
    !isSettled && !isRequested && revenueAmount <= 0;

String settlementStatusLabel({
  required bool isSettled,
  required bool isRequested,
  required int revenueAmount,
  String settledLabel = '정산완료',
}) {
  if (isSettled) return settledLabel;
  if (isRequested) return '정산요청';
  if (revenueAmount <= 0) return '정산 없음';
  return '미정산';
}

Color settlementBadgeColor({
  required bool isSettled,
  required bool isRequested,
  required Color settledColor,
  required Color requestedColor,
  required Color unsettledColor,
  int revenueAmount = -1,
  Color? noRevenueColor,
}) {
  if (isSettled) return settledColor;
  if (isRequested) return requestedColor;
  if (revenueAmount >= 0 &&
      settlementIsNoRevenue(
        isSettled: isSettled,
        isRequested: isRequested,
        revenueAmount: revenueAmount,
      )) {
    return noRevenueColor ?? settlementNoRevenueForeground;
  }
  return unsettledColor;
}
