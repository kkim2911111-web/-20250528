import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/utils/rental_interval_billing.dart' as billing;
import 'package:danjicar_app/utils/rental_pricing.dart';

void main() {
  const pricePerHour = 10000;

  group('hourlyAmountFromMinutes — 1시간 올림', () {
    test('60분 → 1시간', () {
      expect(RentalPricing.hourlyAmountFromMinutes(60, pricePerHour), 10000);
    });

    test('70분 → 2시간', () {
      expect(RentalPricing.hourlyAmountFromMinutes(70, pricePerHour), 20000);
    });

    test('130분 → 3시간', () {
      expect(RentalPricing.hourlyAmountFromMinutes(130, pricePerHour), 30000);
    });
  });

  test('hourly 80분 — interval 요금 2시간 올림', () {
    final start = DateTime(2026, 6, 12, 9, 10);
    final end = DateTime(2026, 6, 12, 10, 30);
    final breakdown = billing.calculateRentalPriceBreakdown(
      pricePerHour: 6000,
      rentalTypes: const [RentalType.hourly],
      type: RentalType.hourly,
      start: start,
      end: end,
    );
    expect(breakdown?.amount, 12000);
    expect(RentalPricing.hourlyAmountFromMinutes(80, 6000), 12000);
  });

  test('2:40~4:50 (130분) — 3시간 × 시급 10,000원', () {
    final start = DateTime(2026, 6, 12, 14, 40);
    final end = DateTime(2026, 6, 12, 16, 50);
    final breakdown = billing.calculateRentalPriceBreakdown(
      pricePerHour: pricePerHour,
      rentalTypes: const [RentalType.hourly],
      type: RentalType.hourly,
      start: start,
      end: end,
    );
    expect(breakdown?.amount, 30000);
  });
}
