import 'package:danjicar_app/models/vehicle.dart';
import 'package:danjicar_app/utils/booking_period_resolver.dart';
import 'package:danjicar_app/utils/rental_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

Vehicle _carnivalMonthly() {
  return const Vehicle(
    id: '28',
    complexId: 'c1',
    name: '카니발9',
    vehicleType: 'MPV',
    serviceType: VehicleServiceType.rental,
    pricePerHour: 0,
    monthlyPrice: 1100000,
    rentalTypes: [RentalType.monthly],
    isAvailable: true,
    carNumber: '116하1712',
  );
}

void main() {
  final startDay = DateTime(2026, 6, 12);

  group('monthly booking opening', () {
    test('반납 달력 7월 이동 범위 — 6/12 시작 시 7월·상한 포함', () {
      final julyDay = DateTime(2026, 7, 15);
      final maxReturn = RentalPricing.maxReturnDay(startDay);

      expect(
        BookingPeriodResolver.dateOnly(julyDay).month,
        7,
      );
      expect(
        BookingPeriodResolver.dateOnly(maxReturn),
        BookingPeriodResolver.dateOnly(RentalPricing.addMonths(startDay, 11)),
      );
    });

    test('35일 선택 — 초과 일요금 없는 월 전용 차는 30일 배수만 허용', () {
      final vehicle = _carnivalMonthly();
      final result = BookingPeriodResolver.resolve(
        startDay: startDay,
        returnDay: startDay.add(const Duration(days: 35)),
        startHour: 9,
      );

      expect(result.valid, isTrue);
      expect(result.rentalType, RentalType.monthly);
      expect(
        RentalPricing.displayUnitPriceLabel(vehicle, result.rentalType),
        '₩1,100,000/월',
      );
      expect(
        RentalPricing.vehicleSupportsBookingPeriod(
          vehicle,
          result.rentalType,
          start: result.start,
          end: result.end,
        ),
        isFalse,
      );
      expect(
        RentalPricing.calculateBasePriceFromIntervalVehicle(
          vehicle,
          result.rentalType,
          start: result.start,
          end: result.end,
        ),
        isNull,
      );
    });

    test('30일 선택 — 월 전용 차 1개월 청구', () {
      final vehicle = _carnivalMonthly();
      final result = BookingPeriodResolver.resolve(
        startDay: startDay,
        returnDay: startDay.add(const Duration(days: 30)),
        startHour: 9,
      );

      expect(result.valid, isTrue);
      expect(result.rentalType, RentalType.monthly);
      expect(
        RentalPricing.calculateBasePriceFromIntervalVehicle(
          vehicle,
          result.rentalType,
          start: result.start,
          end: result.end,
        ),
        1100000,
      );
    });

    test('29일 daily 회귀', () {
      final vehicle = _carnivalMonthly();
      final result = BookingPeriodResolver.resolve(
        startDay: startDay,
        returnDay: startDay.add(const Duration(days: 29)),
        startHour: 9,
      );

      expect(result.valid, isTrue);
      expect(result.rentalType, RentalType.daily);
      expect(result.days, 29);
      expect(vehicle.supportsRentalType(result.rentalType), isFalse);
    });

    test('30일 경계 monthly 전환', () {
      final result = BookingPeriodResolver.resolve(
        startDay: startDay,
        returnDay: startDay.add(const Duration(days: 30)),
        startHour: 9,
      );

      expect(result.valid, isTrue);
      expect(result.rentalType, RentalType.monthly);
      expect(result.months, 1);

      final vehicle = _carnivalMonthly();
      final price = RentalPricing.calculatePrice(
        vehicle,
        RentalType.monthly,
        hours: 0,
        days: 1,
        months: result.months,
      );
      expect(price, 1100000);
    });

    test('월 전용 차량 대표 요금 — ₩0/h 대신 ₩N/월', () {
      final vehicle = _carnivalMonthly();
      expect(
        RentalPricing.displayUnitPriceLabel(vehicle, RentalType.hourly),
        '₩1,100,000/월',
      );
      expect(
        RentalPricing.cardUnitPriceLabel(
          pricePerHour: vehicle.pricePerHour,
          dailyPrice: vehicle.dailyPrice,
          monthlyPrice: vehicle.monthlyPrice,
          rentalTypes: vehicle.rentalTypes,
        ),
        '₩1,100,000/월',
      );
    });

    test('일 전용 차량 카드 요금 — ₩N/일', () {
      expect(
        RentalPricing.cardUnitPriceLabel(
          pricePerHour: 0,
          dailyPrice: 85000,
          rentalTypes: const [RentalType.daily],
        ),
        '₩85,000/일',
      );
    });

    test('rental_types 미설정 + monthly_price — 카드 ₩N/월 추론', () {
      expect(
        RentalPricing.cardUnitPriceLabel(
          pricePerHour: 0,
          monthlyPrice: 1100000,
          rentalTypes: const [RentalType.hourly],
        ),
        '₩1,100,000/월',
      );
    });
  });
}
