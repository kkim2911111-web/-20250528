import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/models/vehicle.dart';
import 'package:danjicar_app/utils/rental_pricing.dart';

Vehicle _vehicle({
  int hourly = 10000,
  int? daily,
  int? monthly,
  List<RentalType> types = const [RentalType.hourly],
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

void main() {
  group('RentalPricing parity (client calculatePrice vs interval base)', () {
    test('hourly — duration picker와 interval 계산 일치', () {
      final vehicle = _vehicle();
      final start = DateTime(2026, 5, 28, 10);
      final end = DateTime(2026, 5, 28, 15);
      final hours = end.difference(start).inHours;

      final fromPicker = RentalPricing.calculatePrice(
        vehicle,
        RentalType.hourly,
        hours: hours,
        days: 0,
        months: 0,
      );
      final fromInterval = RentalPricing.calculateBasePriceFromIntervalVehicle(
        vehicle,
        RentalType.hourly,
        start: start,
        end: end,
      );

      expect(fromInterval, fromPicker);
      expect(fromPicker, 50000);
    });

    test('daily — 폴백 일 요금 (시간×20)', () {
      final vehicle = _vehicle(types: const [RentalType.daily]);
      final start = DateTime(2026, 5, 28, 9);
      final end = start.add(const Duration(days: 3));

      final fromPicker = RentalPricing.calculatePrice(
        vehicle,
        RentalType.daily,
        hours: 0,
        days: 3,
        months: 0,
      );
      final fromInterval = RentalPricing.calculateBasePriceFromIntervalVehicle(
        vehicle,
        RentalType.daily,
        start: start,
        end: end,
      );

      expect(fromInterval, fromPicker);
      expect(fromPicker, 3 * 10000 * 20);
    });

    test('monthly — 명시 월 요금', () {
      final vehicle = _vehicle(
        types: const [RentalType.monthly],
        daily: 150000,
        monthly: 3000000,
      );
      final start = DateTime(2026, 1, 31, 14);
      final end = RentalPricing.addMonths(start, 2);

      final fromPicker = RentalPricing.calculatePrice(
        vehicle,
        RentalType.monthly,
        hours: 0,
        days: 0,
        months: 2,
      );
      final fromInterval = RentalPricing.calculateBasePriceFromIntervalVehicle(
        vehicle,
        RentalType.monthly,
        start: start,
        end: end,
      );

      expect(fromInterval, fromPicker);
      expect(fromPicker, 6000000);
    });

    test('요금 조작 시 interval 검증이 다른 금액을 반환', () {
      final vehicle = _vehicle();
      final start = DateTime(2026, 5, 28, 10);
      final end = DateTime(2026, 5, 28, 13);
      final legit = RentalPricing.calculateBasePriceFromIntervalVehicle(
        vehicle,
        RentalType.hourly,
        start: start,
        end: end,
      );
      expect(legit, 30000);
      expect(legit == 29999, isFalse);
      expect(legit == 30001, isFalse);
    });
  });

  group('rental_type 백필 규칙', () {
    test('<24h → hourly', () {
      final start = DateTime(2026, 5, 1, 9);
      final end = start.add(const Duration(hours: 23));
      expect(
        RentalPricing.inferRentalTypeFromInterval(start: start, end: end),
        RentalType.hourly,
      );
    });

    test('24h~30일 → daily', () {
      final start = DateTime(2026, 5, 1, 9);
      final end = start.add(const Duration(days: 7));
      expect(
        RentalPricing.inferRentalTypeFromInterval(start: start, end: end),
        RentalType.daily,
      );
    });

    test('>30일 → monthly', () {
      final start = DateTime(2026, 5, 1, 9);
      final end = start.add(const Duration(days: 31));
      expect(
        RentalPricing.inferRentalTypeFromInterval(start: start, end: end),
        RentalType.monthly,
      );
    });

    test('정확히 24시간 → daily', () {
      final start = DateTime(2026, 5, 1, 9);
      final end = start.add(const Duration(hours: 24));
      expect(
        RentalPricing.inferRentalTypeFromInterval(start: start, end: end),
        RentalType.daily,
      );
    });
  });

  group('복합 rental_types 차량 탭 필터', () {
    test('hourly+daily 차량 — 양쪽 탭 모두 노출', () {
      final vehicle = _vehicle(
        types: const [RentalType.hourly, RentalType.daily],
      );

      expect(vehicle.supportsRentalType(RentalType.hourly), isTrue);
      expect(vehicle.supportsRentalType(RentalType.daily), isTrue);
      expect(vehicle.supportsRentalType(RentalType.monthly), isFalse);
    });

    test('daily+monthly 차량 — 일/월 탭만', () {
      final vehicle = _vehicle(
        types: const [RentalType.daily, RentalType.monthly],
      );

      expect(vehicle.supportsRentalType(RentalType.hourly), isFalse);
      expect(vehicle.supportsRentalType(RentalType.daily), isTrue);
      expect(vehicle.supportsRentalType(RentalType.monthly), isTrue);
    });
  });
}
