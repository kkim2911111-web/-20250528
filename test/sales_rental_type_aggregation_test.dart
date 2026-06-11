import 'package:danjicar_app/utils/rental_pricing.dart';
import 'package:danjicar_app/utils/sales_return_completed_at.dart';
import 'package:flutter_test/flutter_test.dart';

/// `sales_completed_reservations_v` completed 분기 포함 조건 미러
bool isIncludedInSalesCompletedView({
  required String status,
  DateTime? returnedAt,
  DateTime? actualEndAt,
  DateTime? scheduledEndAt,
  bool isNoShow = false,
}) {
  if (status != 'completed') return false;
  if (isNoShow) {
    return resolveSalesReturnCompletedAt(
          returnedAt: returnedAt,
          actualEndAt: actualEndAt,
          scheduledEndAt: scheduledEndAt,
          isNoShow: true,
        ) !=
        null;
  }
  return resolveSalesReturnCompletedAt(
        returnedAt: returnedAt,
        actualEndAt: actualEndAt,
        scheduledEndAt: scheduledEndAt,
      ) !=
      null;
}

int sumGrossForPeriod({
  required List<Map<String, dynamic>> rows,
  required DateTime periodStart,
  required DateTime periodEnd,
}) {
  var total = 0;
  for (final row in rows) {
    final recognized = row['return_completed_at'] as DateTime?;
    if (recognized == null) continue;
    if (recognized.isBefore(periodStart) || !recognized.isBefore(periodEnd)) {
      continue;
    }
    total += row['gross_amount'] as int? ?? 0;
  }
  return total;
}

void main() {
  group('sales_completed_reservations_v inclusion (rental_type 무관)', () {
    test('hourly completed with returned_at is included', () {
      final returned = DateTime.utc(2026, 5, 28, 3);
      expect(
        isIncludedInSalesCompletedView(
          status: 'completed',
          returnedAt: returned,
          scheduledEndAt: DateTime.utc(2026, 5, 28, 5),
        ),
        isTrue,
      );
      expect(
        resolveSalesReturnCompletedAt(returnedAt: returned),
        returned,
      );
    });

    test('daily completed with only end_at fallback is included', () {
      final endAt = DateTime.utc(2026, 5, 30, 15);
      expect(
        isIncludedInSalesCompletedView(
          status: 'completed',
          scheduledEndAt: endAt,
        ),
        isTrue,
      );
    });

    test('monthly completed with actual_end_at is included', () {
      final actual = DateTime.utc(2026, 6, 15, 1);
      expect(
        isIncludedInSalesCompletedView(
          status: 'completed',
          actualEndAt: actual,
          scheduledEndAt: DateTime.utc(2026, 7, 10, 1),
        ),
        isTrue,
      );
    });

    test('completed without any return timestamp is excluded', () {
      expect(
        isIncludedInSalesCompletedView(status: 'completed'),
        isFalse,
      );
    });
  });

  group('monthly gross sum by return_completed_at period', () {
    test('hourly + daily + monthly completed rows sum in same month', () {
      final periodStart = DateTime.utc(2026, 5, 1);
      final periodEnd = DateTime.utc(2026, 6, 1);

      final rows = [
        {
          'rental_type': RentalType.hourly.dbValue,
          'return_completed_at': DateTime.utc(2026, 5, 10, 12),
          'gross_amount': 15000,
        },
        {
          'rental_type': RentalType.daily.dbValue,
          'return_completed_at': DateTime.utc(2026, 5, 12, 9),
          'gross_amount': 200000,
        },
        {
          'rental_type': RentalType.monthly.dbValue,
          'return_completed_at': DateTime.utc(2026, 5, 20, 6),
          'gross_amount': 1100000,
        },
        {
          'rental_type': RentalType.daily.dbValue,
          'return_completed_at': DateTime.utc(2026, 6, 2, 6),
          'gross_amount': 99999,
        },
      ];

      expect(
        sumGrossForPeriod(
          rows: rows,
          periodStart: periodStart,
          periodEnd: periodEnd,
        ),
        15000 + 200000 + 1100000,
      );
    });
  });
}
