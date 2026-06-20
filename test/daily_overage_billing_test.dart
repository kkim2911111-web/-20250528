import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/models/vehicle.dart';
import 'package:danjicar_app/utils/booking_period_resolver.dart';
import 'package:danjicar_app/utils/daily_rental_duration.dart';
import 'package:danjicar_app/utils/rental_interval_billing.dart';
import 'package:danjicar_app/utils/rental_pricing.dart';

Vehicle _vehicle({
  int? daily,
  int? dailyOverageHourlyRate,
}) {
  return Vehicle(
    id: 'v1',
    name: '테스트',
    complexId: 'c1',
    vehicleType: 'SUV',
    pricePerHour: 5000,
    isAvailable: true,
    dailyPrice: daily,
    dailyOverageHourlyRate: dailyOverageHourlyRate,
    rentalTypes: const [RentalType.daily],
  );
}

void main() {
  group('DailyRentalDurationSplit', () {
    test('1일 + 2시간 30분 — 올림 3시간, 표시는 실제 분', () {
      final start = DateTime(2026, 6, 20, 10);
      final end = DateTime(2026, 6, 21, 12, 30);
      final split = DailyRentalDurationSplit.fromInterval(start: start, end: end);

      expect(split.fullDays, 1);
      expect(split.overageMinutes, 150);
      expect(split.billedOverageHours, 3);
      expect(split.formatLabel(), '1일 2시간 30분');
    });
  });

  group('1일 렌트 초과 시간당 요금', () {
    final start = DateTime(2026, 6, 20, 10);
    final end = DateTime(2026, 6, 21, 12, 30);
    final vehicle = _vehicle(daily: 100000, dailyOverageHourlyRate: 10000);

    test('총 결제금액 ₩130,000 (기본 + 올림 3시간)', () {
      final breakdown = RentalPricing.calculateBasePriceBreakdownFromVehicle(
        vehicle,
        RentalType.daily,
        start: start,
        end: end,
      );

      expect(breakdown, isNotNull);
      expect(breakdown!.amount, 130000);
      expect(breakdown.baseAmount, 100000);
      expect(breakdown.overageAmount, 30000);
      expect(breakdown.billedOverageHours, 3);
    });

    test('확인 화면 요금 라벨', () {
      final breakdown = RentalPricing.calculateBasePriceBreakdownFromVehicle(
        vehicle,
        RentalType.daily,
        start: start,
        end: end,
      );

      expect(
        breakdown!.dailyOverageConfirmationLabel(
          fullDays: 1,
          formatWon: (n) => n.toString().replaceAllMapped(
                RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
                (m) => '${m[1]},',
              ),
        ),
        '1일 ₩100,000 + 초과 3시간 ₩30,000',
      );
    });

    test('기간 요약 — 실제 선택 시간(올림 미적용)', () {
      expect(
        RentalPricing.formatDurationLabelFromInterval(start: start, end: end),
        '1일 2시간 30분',
      );
    });

    test('초과요금 미설정 차량 — 초과 구간 요금 산출 불가', () {
      final noRate = _vehicle(daily: 100000);
      final price = RentalPricing.calculateBasePriceFromIntervalVehicle(
        noRate,
        RentalType.daily,
        start: start,
        end: end,
      );
      expect(price, isNull);
    });

    test('초과요금 미설정 차량 — 24h 배수는 허용', () {
      final noRate = _vehicle(daily: 100000);
      final exactEnd = DateTime(2026, 6, 21, 10);
      final price = RentalPricing.calculateBasePriceFromIntervalVehicle(
        noRate,
        RentalType.daily,
        start: start,
        end: exactEnd,
      );
      expect(price, 100000);
    });

    test('반납 시각 별도 선택 — BookingPeriodResolver', () {
      final result = BookingPeriodResolver.resolve(
        startDay: DateTime(2026, 6, 20),
        returnDay: DateTime(2026, 6, 21),
        startHour: 10,
        returnHour: 12,
      );
      expect(result.valid, isTrue);
      expect(result.rentalType, RentalType.daily);
      expect(result.days, 1);
      expect(result.end, DateTime(2026, 6, 21, 12));
    });
  });

  group('vehicleSupportsBookingPeriod', () {
    test('초과 구간 — rate 있으면 지원', () {
      final v = _vehicle(daily: 100000, dailyOverageHourlyRate: 10000);
      expect(
        RentalPricing.vehicleSupportsBookingPeriod(
          v,
          RentalType.daily,
          start: DateTime(2026, 6, 20, 10),
          end: DateTime(2026, 6, 21, 12, 30),
        ),
        isTrue,
      );
    });

    test('초과 구간 — rate 없으면 미지원', () {
      final v = _vehicle(daily: 100000);
      expect(
        RentalPricing.vehicleSupportsBookingPeriod(
          v,
          RentalType.daily,
          start: DateTime(2026, 6, 20, 10),
          end: DateTime(2026, 6, 21, 12, 30),
        ),
        isFalse,
      );
    });
  });
}
