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

    test('30일 초과 일수 → 전화 문의', () {
      final result = BookingPeriodResolver.resolve(
        startDay: startDay,
        returnDay: startDay.add(const Duration(days: 30)),
        startHour: 9,
      );
      expect(result.valid, isFalse);
      expect(result.inquiry, BookingPeriodInquiry.dailyOverMax);
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

    test('31일(비정형) → 전화 문의', () {
      final result = BookingPeriodResolver.resolve(
        startDay: startDay,
        returnDay: startDay.add(const Duration(days: 31)),
        startHour: 9,
      );
      expect(result.valid, isFalse);
      expect(result.inquiry, BookingPeriodInquiry.monthlyOverMax);
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
