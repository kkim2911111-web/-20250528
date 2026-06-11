import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/staff_profile.dart';
import '../theme/danji_colors.dart';
import '../utils/rental_detail_navigation.dart';
import 'rental_type_badge.dart';

/// 관리자 매출 — 차량별 선택 월 완료 건 바텀시트
Future<void> showVehicleMonthSalesSheet({
  required BuildContext context,
  required String vehicleName,
  required int year,
  required int month,
  required List<VehicleSalesRentalItem> items,
}) async {
  final won = NumberFormat('#,###');
  final monthLabel = DateFormat('yyyy년 M월').format(DateTime(year, month));
  final dateTimeFormat = DateFormat('M/d HH:mm');
  final total = items.fold<int>(0, (sum, e) => sum + e.grossAmount);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DanjiColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicleName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    monthLabel,
                    style: const TextStyle(
                      color: DanjiColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    items.isEmpty
                        ? '이번 달 완료 건 없음'
                        : '완료 ${items.length}건 · 매출 ₩${won.format(total)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    '이번 달 완료 건 없음',
                    style: TextStyle(color: DanjiColors.textSecondary),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.55,
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final item = items[index];
                    final sortAt = item.sortAt?.toLocal();
                    final dateLabel = sortAt == null
                        ? '—'
                        : dateTimeFormat.format(sortAt);

                    return Material(
                      color: DanjiColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: item.reservationId == null
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                openStaffRentalDetail(
                                  context,
                                  reservationId: item.reservationId!,
                                );
                              },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: DanjiColors.border),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RentalTypeBadge(rentalTypeDb: item.rentalType),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      dateLabel,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.renterName,
                                      style: const TextStyle(
                                        color: DanjiColors.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '₩${won.format(item.grossAmount)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: DanjiColors.buttonBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    },
  );
}
