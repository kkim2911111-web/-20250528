import 'package:danjicar_app/utils/booking_period_resolver.dart';
import 'package:danjicar_app/utils/rental_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final startDay = DateTime(2026, 6, 12);

  group('BookingPeriodResolver hourly', () {
    test('same day 9~10 → hourly 1h', () {
      final result = BookingPeriodResolver.resolve(
        startDay: startDay,
        returnDay: startDay,
        startHour: 9,
        endHour: 10,
      );
      expect(result.valid, isTrue);
      expect(result.rentalType, RentalType.hourly);
      expect(result.hours, 1);
    });

    test('same day invalid end → invalid', () {
      final result = BookingPeriodResolver.resolve(
        startDay: startDay,
        returnDay: startDay,
        startHour: 10,
        endHour: 10,
      );
      expect(result.valid, isFalse);
    });
  });

  group('BookingPeriodResolver daily', () {
    test('return +2 days same hour → daily 2일', () {
      final result = BookingPeriodResolver.resolve(
        startDay: startDay,
        returnDay: startDay.add(const Duration(days: 2)),
        startHour: 14,
      );
      expect(result.valid, isTrue);
      expect(result.rentalType, RentalType.daily);
      expect(result.days, 2);
      expect(result.start.hour, 14);
      expect(result.end.hour, 14);
    });

    test('29일 → daily 유지', () {
      final result = BookingPeriodResolver.resolve(
        startDay: startDay,
        returnDay: startDay.add(const Duration(days: 29)),
        startHour: 9,
      );
      expect(result.valid, isTrue);
      expect(result.rentalType, RentalType.daily);
      expect(result.days, 29);
    });
  });

  group('BookingPeriodResolver monthly', () {
    test('정확히 2개월 → monthly 판정', () {
      final result = BookingPeriodResolver.resolve(
        startDay: startDay,
        returnDay: RentalPricing.addMonths(startDay, 2),
        startHour: 9,
      );
      expect(result.valid, isTrue);
      expect(result.rentalType, RentalType.monthly);
      expect(result.months, 2);
    });

    test('30일 경계 → monthly 1개월', () {
      final result = BookingPeriodResolver.resolve(
        startDay: startDay,
        returnDay: startDay.add(const Duration(days: 30)),
        startHour: 9,
      );
      expect(result.valid, isTrue);
      expect(result.rentalType, RentalType.monthly);
      expect(result.months, 1);
    });

    test('35일(비정수 월) → monthly 2개월 청구', () {
      final result = BookingPeriodResolver.resolve(
        startDay: startDay,
        returnDay: startDay.add(const Duration(days: 35)),
        startHour: 9,
      );
      expect(result.valid, isTrue);
      expect(result.rentalType, RentalType.monthly);
      expect(result.months, 2);
    });

    test('반납 달력 상한 — 시작일+11개월까지 선택 가능', () {
      final maxReturn = RentalPricing.maxReturnDay(startDay);
      final within = BookingPeriodResolver.resolve(
        startDay: startDay,
        returnDay: maxReturn,
        startHour: 9,
      );
      expect(within.valid, isTrue);
      expect(within.inquiry, isNull);

      final over = BookingPeriodResolver.resolve(
        startDay: startDay,
        returnDay: maxReturn.add(const Duration(days: 1)),
        startHour: 9,
      );
      expect(over.valid, isFalse);
      expect(over.inquiry, BookingPeriodInquiry.monthlyOverMax);
    });

    test('12개월 초과 → 전화 문의', () {
      final result = BookingPeriodResolver.resolve(
        startDay: startDay,
        returnDay: RentalPricing.addMonths(startDay, 12),
        startHour: 9,
      );
      expect(result.valid, isFalse);
      expect(result.inquiry, BookingPeriodInquiry.monthlyOverMax);
    });
  });
}
