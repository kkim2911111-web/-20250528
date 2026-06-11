import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/models/vehicle.dart';
import 'package:danjicar_app/utils/rental_interval_billing.dart';
import 'package:danjicar_app/utils/rental_pricing.dart';

Vehicle _vehicle({
  int hourly = 10000,
  int? daily,
  int? monthly,
  int? excess,
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
    monthlyExcessDailyPrice: excess,
    rentalTypes: types,
  );
}

DateTime _start() => DateTime(2026, 5, 1, 9);

DateTime _endAfterDays(int days) => _start().add(Duration(days: days));

int? _price(Vehicle v, RentalType type, int days) {
  final start = _start();
  final end = _endAfterDays(days);
  return RentalPricing.calculateBasePriceFromIntervalVehicle(
    v,
    type,
    start: start,
    end: end,
  );
}

void main() {
  group('케이스 1 — 일+월 모두 운영', () {
    final vehicle = _vehicle(
      daily: 50000,
      monthly: 500000,
      types: const [RentalType.daily, RentalType.monthly],
    );

    test('일 탭 경계값 10/11/12일', () {
      expect(_price(vehicle, RentalType.daily, 10), 500000);
      expect(_price(vehicle, RentalType.daily, 11), 500000);
      expect(_price(vehicle, RentalType.daily, 12), 500000);
    });

    test('월 탭 경계값 30/31/35/41/60일', () {
      expect(_price(vehicle, RentalType.monthly, 30), 500000);
      expect(_price(vehicle, RentalType.monthly, 31), 550000);
      expect(_price(vehicle, RentalType.monthly, 35), 750000);
      expect(_price(vehicle, RentalType.monthly, 41), 1000000);
      expect(_price(vehicle, RentalType.monthly, 60), 1000000);
    });

    test('12일 월요금 캡 플래그', () {
      final breakdown = RentalPricing.calculateBasePriceBreakdownFromVehicle(
        vehicle,
        RentalType.daily,
        start: _start(),
        end: _endAfterDays(12),
      );
      expect(breakdown?.monthlyCapApplied, isTrue);
    });
  });

  group('케이스 2 — 월만 운영 + 초과 일요금', () {
    final vehicle = _vehicle(
      daily: 50000,
      monthly: 1500000,
      excess: 20000,
      types: const [RentalType.monthly],
    );

    test('경계값 30/31/35/41/60일', () {
      expect(_price(vehicle, RentalType.monthly, 30), 1500000);
      expect(_price(vehicle, RentalType.monthly, 31), 1520000);
      expect(_price(vehicle, RentalType.monthly, 35), 1600000);
      expect(_price(vehicle, RentalType.monthly, 41), 1720000);
      expect(_price(vehicle, RentalType.monthly, 60), 3000000);
    });

    test('35일 E2E 실결제 ₩1,600,000', () {
      expect(_price(vehicle, RentalType.monthly, 35), 1600000);
    });
  });

  group('월만 운영 + 초과 일요금 없음', () {
    final vehicle = _vehicle(
      monthly: 1500000,
      types: const [RentalType.monthly],
    );

    test('30일 배수만 허용', () {
      expect(
        vehicleSupportsBookingPeriod(
          rentalTypes: vehicle.rentalTypes,
          monthlyExcessDailyPrice: vehicle.monthlyExcessDailyPrice,
          type: RentalType.monthly,
          start: _start(),
          end: _endAfterDays(30),
        ),
        isTrue,
      );
      expect(
        vehicleSupportsBookingPeriod(
          rentalTypes: vehicle.rentalTypes,
          monthlyExcessDailyPrice: vehicle.monthlyExcessDailyPrice,
          type: RentalType.monthly,
          start: _start(),
          end: _endAfterDays(35),
        ),
        isFalse,
      );
      expect(_price(vehicle, RentalType.monthly, 35), isNull);
    });
  });

  group('일만 운영', () {
    final vehicle = _vehicle(
      daily: 50000,
      types: const [RentalType.daily],
    );

    test('일수×일요금', () {
      expect(_price(vehicle, RentalType.daily, 10), 500000);
    });
  });

  group('취소선 ₩0 미표시', () {
    test('compare price 0이면 null', () {
      final vehicle = _vehicle(
        hourly: 0,
        daily: 50000,
        types: const [RentalType.daily],
      );
      final compare = RentalPricing.comparisonStrikethroughPrice(
        vehicle,
        RentalType.daily,
        hours: 0,
        days: 3,
        months: 0,
        start: _start(),
        end: _endAfterDays(3),
      );
      expect(compare, isNull);
    });
  });
}
