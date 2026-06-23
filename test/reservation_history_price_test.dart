import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/models/reservation.dart';

Reservation _res({
  int totalPrice = 10000,
  int extensionPriceTotal = 0,
  int? overdueOverageAmount,
  int? overdueOverageHours,
  bool overdueOverageCharged = false,
  DateTime? startAt,
  DateTime? endAt,
}) {
  return Reservation(
    id: '1',
    userId: 'u',
    vehicleId: 'v',
    startAt: startAt,
    endAt: endAt,
    totalPrice: totalPrice,
    status: 'returned',
    extensionPriceTotal: extensionPriceTotal,
    overdueOverageAmount: overdueOverageAmount,
    overdueOverageHours: overdueOverageHours,
    overdueOverageCharged: overdueOverageCharged,
  );
}

void main() {
  group('이용내역 결제 합계', () {
    test('KG-2606-052 — 기본 1만 + 초과 4만 = 5만', () {
      final r = _res(
        totalPrice: 15000,
        overdueOverageAmount: 40000,
        overdueOverageHours: 4,
        overdueOverageCharged: true,
        startAt: DateTime(2026, 6, 12, 17, 0),
        endAt: DateTime(2026, 6, 12, 18, 0),
      );

      expect(r.historyPaidTotal, 55000);
      expect(r.showHistoryPriceBreakdown, isTrue);
      expect(
        r.historyPriceParts.map((p) => p.label).toList(),
        ['기본요금', '초과요금'],
      );
      expect(r.historyPriceParts[0].hours, 1);
      expect(r.historyPriceParts[1].hours, 4);
    });

    test('KG-2606-053 — 기본 1만 + 초과 1만 = 2만', () {
      final r = _res(
        overdueOverageAmount: 10000,
        overdueOverageHours: 1,
        overdueOverageCharged: true,
      );

      expect(r.historyPaidTotal, 20000);
    });

    test('KG-2606-054 — 초과요금 null, 기본만', () {
      final r = _res();

      expect(r.historyPaidTotal, 10000);
      expect(r.showHistoryPriceBreakdown, isFalse);
    });

    test('연장요금 포함 — total_price에 반영 + 분해', () {
      final r = _res(totalPrice: 20000, extensionPriceTotal: 10000);

      expect(r.baseRentalPrice, 10000);
      expect(r.historyPaidTotal, 20000);
      expect(r.showHistoryPriceBreakdown, isTrue);
    });

    test('미청구 초과요금은 합계 제외', () {
      final r = _res(overdueOverageAmount: 40000, overdueOverageHours: 4);

      expect(r.historyPaidTotal, 10000);
      expect(r.showHistoryPriceBreakdown, isFalse);
    });

    test('초과 hours null/0 — 분해에 초과요금 생략', () {
      final r = _res(
        overdueOverageAmount: 40000,
        overdueOverageCharged: true,
      );

      expect(
        r.historyPriceParts.map((p) => p.label).toList(),
        ['기본요금'],
      );
    });
  });
}
