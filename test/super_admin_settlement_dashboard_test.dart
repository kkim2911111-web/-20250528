import 'package:danjicar_app/models/super_admin_models.dart';
import 'package:danjicar_app/utils/super_admin_settlement_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';

SuperAdminRevenueRow _row({
  bool isSettled = false,
  bool isRequested = false,
  int grossRevenue = 0,
  int extensionRevenue = 0,
}) {
  return SuperAdminRevenueRow(
    complexId: 'c1',
    complexName: '테스트단지',
    year: 2026,
    month: 4,
    grossRevenue: grossRevenue,
    extensionRevenue: extensionRevenue,
    isSettled: isSettled,
    isRequested: isRequested,
  );
}

void main() {
  group('superAdminSettlementDashboardPeriod', () {
    test('uses previous calendar month', () {
      expect(
        superAdminSettlementDashboardPeriod(DateTime(2026, 5, 28)),
        (year: 2026, month: 4),
      );
      expect(
        superAdminSettlementDashboardPeriod(DateTime(2026, 1, 3)),
        (year: 2025, month: 12),
      );
    });
  });

  group('SuperAdminSettlementDashboardCard', () {
    test('prioritizes settlement requests', () {
      final card = SuperAdminSettlementDashboardCard.fromRevenueRows(
        [
          _row(isRequested: true, grossRevenue: 10000),
          _row(grossRevenue: 20000),
        ],
        year: 2026,
        month: 4,
      );

      expect(card.kind, SuperAdminSettlementDashboardKind.requested);
      expect(card.count, 1);
      expect(card.label, '정산요청');
      expect(card.value, '1건');
    });

    test('shows unsettled when no requests', () {
      final card = SuperAdminSettlementDashboardCard.fromRevenueRows(
        [_row(grossRevenue: 5000), _row(isSettled: true, grossRevenue: 3000)],
        year: 2026,
        month: 4,
      );

      expect(card.kind, SuperAdminSettlementDashboardKind.unsettled);
      expect(card.count, 1);
      expect(card.label, '미정산');
    });

    test('shows complete when settled or zero revenue', () {
      final allSettled = SuperAdminSettlementDashboardCard.fromRevenueRows(
        [_row(isSettled: true, grossRevenue: 9000)],
        year: 2026,
        month: 4,
      );
      expect(allSettled.kind, SuperAdminSettlementDashboardKind.complete);
      expect(allSettled.value, '완료');

      final zeroRevenue = SuperAdminSettlementDashboardCard.fromRevenueRows(
        [_row(), _row(isSettled: false)],
        year: 2026,
        month: 4,
      );
      expect(zeroRevenue.kind, SuperAdminSettlementDashboardKind.complete);
    });
  });
}
