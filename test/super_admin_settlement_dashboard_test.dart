import 'package:danjicar_app/models/super_admin_models.dart';
import 'package:danjicar_app/utils/super_admin_settlement_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';

SuperAdminRevenueRow _row({
  String complexId = 'c1',
  bool isSettled = false,
  bool isRequested = false,
  int grossRevenue = 0,
  int extensionRevenue = 0,
  int year = 2026,
  int month = 4,
}) {
  return SuperAdminRevenueRow(
    complexId: complexId,
    complexName: '테스트단지',
    year: year,
    month: month,
    grossRevenue: grossRevenue,
    extensionRevenue: extensionRevenue,
    isSettled: isSettled,
    isRequested: isRequested,
  );
}

void main() {
  group('SuperAdminSettlementDashboardCard.fromMonthlySnapshots', () {
    test('prioritizes requests and navigates to oldest pending month', () {
      final card = SuperAdminSettlementDashboardCard.fromMonthlySnapshots(
        [
          (
            year: 2026,
            month: 3,
            rows: [_row(year: 2026, month: 3, grossRevenue: 5000)],
          ),
          (
            year: 2026,
            month: 5,
            rows: [
              _row(
                complexId: 'c2',
                year: 2026,
                month: 5,
                isRequested: true,
                grossRevenue: 10000,
              ),
            ],
          ),
        ],
        now: DateTime(2026, 5, 28),
      );

      expect(card.kind, SuperAdminSettlementDashboardKind.requested);
      expect(card.count, 1);
      expect(card.label, '정산요청');
      expect(card.value, '1건');
      expect((card.year, card.month), (2026, 3));
    });

    test('shows unsettled across months when no requests', () {
      final card = SuperAdminSettlementDashboardCard.fromMonthlySnapshots(
        [
          (
            year: 2026,
            month: 2,
            rows: [
              _row(
                complexId: 'c2',
                year: 2026,
                month: 2,
                grossRevenue: 7000,
              ),
            ],
          ),
          (
            year: 2026,
            month: 4,
            rows: [_row(grossRevenue: 5000), _row(isSettled: true, grossRevenue: 3000)],
          ),
        ],
        now: DateTime(2026, 5, 28),
      );

      expect(card.kind, SuperAdminSettlementDashboardKind.unsettled);
      expect(card.count, 2);
      expect(card.label, '미정산');
      expect((card.year, card.month), (2026, 2));
    });

    test('shows complete when every revenue complex is settled', () {
      final card = SuperAdminSettlementDashboardCard.fromMonthlySnapshots(
        [
          (
            year: 2026,
            month: 4,
            rows: [_row(isSettled: true, grossRevenue: 9000)],
          ),
          (
            year: 2026,
            month: 5,
            rows: [
              _row(
                complexId: 'c2',
                year: 2026,
                month: 5,
                isSettled: true,
                grossRevenue: 12000,
              ),
            ],
          ),
        ],
        now: DateTime(2026, 5, 28),
      );

      expect(card.kind, SuperAdminSettlementDashboardKind.complete);
      expect(card.value, '완료');
      expect((card.year, card.month), (2026, 5));
    });

    test('shows none when no month has revenue', () {
      final card = SuperAdminSettlementDashboardCard.fromMonthlySnapshots(
        [
          (year: 2026, month: 4, rows: [_row()]),
          (year: 2026, month: 5, rows: [_row(isSettled: false)]),
        ],
        now: DateTime(2026, 5, 28),
      );

      expect(card.kind, SuperAdminSettlementDashboardKind.none);
      expect(card.value, '없음');
      expect((card.year, card.month), (2026, 5));
    });
  });
}
