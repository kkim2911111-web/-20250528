import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/models/vehicle.dart';
import 'package:danjicar_app/utils/booking_vehicle_price_display.dart';
import 'package:danjicar_app/utils/rental_pricing.dart';
import 'package:danjicar_app/utils/reservation_display.dart';
import 'package:danjicar_app/utils/vehicle_rental_type_price_guard.dart';

Vehicle _vehicle({
  int hourly = 10000,
  int? daily,
  int? monthly,
  List<RentalType> types = const [RentalType.daily, RentalType.monthly],
}) {
  return Vehicle(
    id: 'v1',
    name: '테스트',
    complexId: 'c1',
    vehicleType: 'SUV',
    pricePerHour: hourly,
    isAvailable: true,
    dailyPrice: daily,
    monthlyPrice: monthly,
    rentalTypes: types,
  );
}

DateTime _start() => DateTime(2026, 5, 1, 9);

void main() {
  group('기간 라벨', () {
    test('30/35/38/60일', () {
      expect(RentalPricing.formatDurationLabelFromDays(30), '1개월');
      expect(RentalPricing.formatDurationLabelFromDays(35), '1개월 5일');
      expect(RentalPricing.formatDurationLabelFromDays(38), '1개월 8일');
      expect(RentalPricing.formatDurationLabelFromDays(60), '2개월');
    });

    test('interval 기준 라벨', () {
      final start = _start();
      expect(
        RentalPricing.formatDurationLabelFromInterval(
          start: start,
          end: start.add(const Duration(days: 35)),
        ),
        '1개월 5일',
      );
    });
  });

  group('차량 카드 가격 표시', () {
    test('일+월 차량 — 취소선·절약 두 줄', () {
      final vehicle = _vehicle(daily: 50000, monthly: 500000);
      final start = _start();
      final end = start.add(const Duration(days: 35));
      final lines = buildBookingVehiclePriceLines(
        vehicle,
        RentalType.monthly,
        start: start,
        end: end,
      );
      expect(lines, isNotNull);
      expect(lines!.showDailyCompare, isTrue);
      expect(lines.dailyCompareAmount, 35 * 50000);
      expect(lines.appliedAmount, 750000);
      expect(lines.showSavings, isTrue);
      expect(lines.savings, 35 * 50000 - 750000);
    });

    test('월 전용 차량 — 월 적용가만', () {
      final vehicle = _vehicle(
        monthly: 1500000,
        types: const [RentalType.monthly],
      );
      final start = _start();
      final end = start.add(const Duration(days: 30));
      final lines = buildBookingVehiclePriceLines(
        vehicle,
        RentalType.monthly,
        start: start,
        end: end,
      );
      expect(lines, isNotNull);
      expect(lines!.showDailyCompare, isFalse);
      expect(lines.appliedAmount, 1500000);
      expect(lines.showSavings, isFalse);
    });
  });

  group('예약·결제 완료 요약', () {
    test('차량명 · 기간', () {
      expect(
        formatBookingSummaryLine(
          vehicleName: '카니발9',
          durationLabel: '1개월 5일',
        ),
        '카니발9 · 1개월 5일',
      );
    });
  });

  group('요금 미입력 토글 ON 저장 가드', () {
    test('일렌트 ON + 요금 없음', () {
      final missing = VehicleRentalTypePriceGuard.findTypesMissingPrice(
        types: {RentalType.daily, RentalType.monthly},
        hourlyPrice: 0,
        dailyPriceText: '',
        monthlyPriceText: '1500000',
      );
      expect(missing, [RentalType.daily]);
      expect(
        VehicleRentalTypePriceGuard.messageFor(RentalType.daily),
        '일렌트가 켜져 있지만 1일 요금이 입력되지 않았습니다',
      );
    });

    test('시간·월 요금 0', () {
      final missing = VehicleRentalTypePriceGuard.findTypesMissingPrice(
        types: RentalType.values.toSet(),
        hourlyPrice: 0,
        dailyPriceText: '50000',
        monthlyPriceText: '0',
      );
      expect(missing, contains(RentalType.hourly));
      expect(missing, contains(RentalType.monthly));
      expect(missing, isNot(contains(RentalType.daily)));
    });
  });
}
