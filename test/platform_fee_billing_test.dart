import 'package:danjicar_app/models/super_admin_models.dart';
import 'package:danjicar_app/utils/platform_fee_billing.dart';
import 'package:danjicar_app/widgets/super_admin_complex_revenue_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isVehicleBillableForMonth', () {
    test('includes vehicle registered mid-month for full month fee', () {
      expect(
        isVehicleBillableForMonth(
          registeredAt: DateTime(2026, 5, 15),
          year: 2026,
          month: 5,
          asOf: DateTime(2026, 5, 28),
        ),
        isTrue,
      );
    });

    test('excludes vehicle registered after month end', () {
      expect(
        isVehicleBillableForMonth(
          registeredAt: DateTime(2026, 6, 1),
          year: 2026,
          month: 5,
          asOf: DateTime(2026, 5, 28),
        ),
        isFalse,
      );
    });

    test('includes vehicle deactivated mid-month in that month', () {
      expect(
        isVehicleBillableForMonth(
          registeredAt: DateTime(2026, 4, 1),
          deactivatedAt: DateTime(2026, 5, 20),
          year: 2026,
          month: 5,
          asOf: DateTime(2026, 5, 28),
        ),
        isTrue,
      );
    });

    test('excludes vehicle deactivated before month start', () {
      expect(
        isVehicleBillableForMonth(
          registeredAt: DateTime(2026, 3, 1),
          deactivatedAt: DateTime(2026, 4, 30),
          year: 2026,
          month: 5,
          asOf: DateTime(2026, 5, 28),
        ),
        isFalse,
      );
    });

    test('future month uses current active vehicles only', () {
      expect(
        isVehicleBillableForMonth(
          registeredAt: DateTime(2026, 5, 1),
          year: 2026,
          month: 7,
          asOf: DateTime(2026, 5, 28),
        ),
        isTrue,
      );
      expect(
        isVehicleBillableForMonth(
          registeredAt: DateTime(2026, 5, 1),
          deactivatedAt: DateTime(2026, 5, 10),
          year: 2026,
          month: 7,
          asOf: DateTime(2026, 5, 28),
        ),
        isFalse,
      );
    });
  });

  group('countBillableVehiclesForMonth — May 2026 snapshot', () {
    final vehicles = [
      (
        registeredAt: DateTime(2026, 4, 1),
        deactivatedAt: null as DateTime?,
      ),
      (
        registeredAt: DateTime(2026, 5, 12),
        deactivatedAt: null as DateTime?,
      ),
      (
        registeredAt: DateTime(2026, 3, 1),
        deactivatedAt: DateTime(2026, 5, 20),
      ),
      (
        registeredAt: DateTime(2026, 3, 1),
        deactivatedAt: DateTime(2026, 4, 30),
      ),
      (
        registeredAt: DateTime(2026, 6, 2),
        deactivatedAt: null as DateTime?,
      ),
    ];

    test('counts vehicles active during May (no proration)', () {
      expect(
        countBillableVehiclesForMonth(
          vehicles,
          year: 2026,
          month: 5,
          asOf: DateTime(2026, 5, 28),
        ),
        3,
      );
    });

    test('platform fee is count × 100000', () {
      const count = 3;
      expect(platformFeeAmount(count), 300000);
    });
  });

  group('per-complex totals match dashboard sum', () {
    SuperAdminRevenueRow row(
      String id,
      String name,
      int vehicles, {
      int revenue = 0,
    }) {
      return SuperAdminRevenueRow(
        complexId: id,
        complexName: name,
        year: 2026,
        month: 5,
        grossRevenue: revenue,
        billableVehicleCount: vehicles,
      );
    }

    test('sum of platformFeeAmount equals total monthly fee', () {
      final rows = [
        row('a', '단지A', 5, revenue: 490000),
        row('b', '단지B', 3, revenue: 200000),
        row('c', '단지C', 0, revenue: 0),
      ];

      final totalFee =
          rows.fold<int>(0, (sum, r) => sum + r.platformFeeAmount);

      expect(totalFee, (5 + 3 + 0) * platformFeePerVehicle);
      expect(totalFee, 800000);
    });
  });

  group('sortComplexRevenueRows', () {
    SuperAdminRevenueRow rev(String id, String name, int revenue) {
      return SuperAdminRevenueRow(
        complexId: id,
        complexName: name,
        year: 2026,
        month: 5,
        grossRevenue: revenue,
      );
    }

    test('sorts by revenue desc, zero revenue at bottom', () {
      final sorted = sortComplexRevenueRows([
        rev('z', '제로단지', 0),
        rev('b', '중간단지', 100),
        rev('a', '최고단지', 500),
        rev('c', '또제로', 0),
      ]);

      expect(
        sorted.map((r) => r.complexName).toList(),
        ['최고단지', '중간단지', '또제로', '제로단지'],
      );
    });
  });

  group('isPlatformFeeEstimateMonth', () {
    test('marks future months as estimate', () {
      expect(
        isPlatformFeeEstimateMonth(
          year: 2026,
          month: 7,
          asOf: DateTime(2026, 5, 28),
        ),
        isTrue,
      );
      expect(
        isPlatformFeeEstimateMonth(
          year: 2026,
          month: 5,
          asOf: DateTime(2026, 5, 28),
        ),
        isFalse,
      );
    });
  });
}
