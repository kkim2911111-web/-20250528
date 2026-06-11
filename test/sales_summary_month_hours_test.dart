import 'package:danjicar_app/models/staff_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SalesSummary.monthHoursFor uses calendar days', () {
    expect(SalesSummary.monthHoursFor(year: 2026, month: 6), 720);
    expect(SalesSummary.monthHoursFor(year: 2026, month: 2), 672);
  });

  test('SalesSummary.fromRpc prefers month_hours from RPC', () {
    final summary = SalesSummary.fromRpc(
      {
        'total_revenue': 1000,
        'reservation_count': 1,
        'month_hours': 720,
        'rows': [],
        'utilization_rows': [],
      },
      year: 2026,
      month: 6,
    );

    expect(summary.monthHours, 720);
  });

  test('VehicleSalesRentalItem.fromRpc parses fields', () {
    final item = VehicleSalesRentalItem.fromRpc({
      'reservation_id': 'abc',
      'renter_name': '홍길동',
      'rental_type': 'monthly',
      'sort_at': '2026-06-11T10:30:00.000Z',
      'gross_amount': 50000,
    });

    expect(item.reservationId, 'abc');
    expect(item.renterName, '홍길동');
    expect(item.rentalType, 'monthly');
    expect(item.grossAmount, 50000);
    expect(item.sortAt, isNotNull);
  });
}
