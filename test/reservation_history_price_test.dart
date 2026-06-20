import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/models/reservation.dart';

Reservation _res({
  int totalPrice = 10000,
  int extensionPriceTotal = 0,
  int? overdueOverageAmount,
  bool overdueOverageCharged = false,
}) {
  return Reservation(
    id: '1',
    userId: 'u',
    vehicleId: 'v',
    totalPrice: totalPrice,
    status: 'returned',
    extensionPriceTotal: extensionPriceTotal,
    overdueOverageAmount: overdueOverageAmount,
    overdueOverageCharged: overdueOverageCharged,
  );
}

void main() {
  group('이용내역 결제 합계', () {
    test('KG-2606-052 — 기본 1만 + 초과 4만 = 5만', () {
      final r = _res(
        overdueOverageAmount: 40000,
        overdueOverageCharged: true,
      );

      expect(r.historyPaidTotal, 50000);
      expect(r.showHistoryPriceBreakdown, isTrue);
      expect(
        r.historyPriceParts.map((p) => p.label).toList(),
        ['기본요금', '초과요금'],
      );
    });

    test('KG-2606-053 — 기본 1만 + 초과 1만 = 2만', () {
      final r = _res(
        overdueOverageAmount: 10000,
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
      final r = _res(overdueOverageAmount: 40000);

      expect(r.historyPaidTotal, 10000);
      expect(r.showHistoryPriceBreakdown, isFalse);
    });
  });
}
