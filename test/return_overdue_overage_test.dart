import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/utils/daily_rental_duration.dart';
import 'package:danjicar_app/utils/return_overdue_overage.dart';

void main() {
  group('반납 지연 초과 이용 요금', () {
    test('2시간 10분 지연 — 3시간 올림', () {
      final scheduledEnd = DateTime(2026, 6, 20, 18);
      final returnedAt = scheduledEnd.add(const Duration(hours: 2, minutes: 10));

      final split = DailyRentalDurationSplit.fromInterval(
        start: scheduledEnd,
        end: returnedAt,
      );

      expect(split.billedOverageHours, 3);
      expect(split.overageMinutes, 130);
    });

    test('2시간 10분 지연 × ₩10,000/시간 = ₩30,000', () {
      const hourlyRate = 10000;
      final scheduledEnd = DateTime(2026, 6, 20, 18);
      final returnedAt = scheduledEnd.add(const Duration(hours: 2, minutes: 10));

      final split = DailyRentalDurationSplit.fromInterval(
        start: scheduledEnd,
        end: returnedAt,
      );

      expect(split.billedOverageHours * hourlyRate, 30000);
    });
  });

  group('resolve_return_overdue_hourly_rate (rental_type 기준)', () {
    test('hourly — coalesce(hourly_rate, price_per_hour)', () {
      expect(
        ReturnOverdueOverageCalc.resolveHourlyRate(
          rentalType: 'hourly',
          hourlyRate: 10000,
          pricePerHour: 8000,
          dailyOverageHourlyRate: 50000,
        ),
        10000,
      );

      expect(
        ReturnOverdueOverageCalc.resolveHourlyRate(
          rentalType: 'hourly',
          pricePerHour: 10000,
          dailyOverageHourlyRate: 50000,
        ),
        10000,
      );
    });

    test('daily — daily_overage_hourly_rate만 사용', () {
      expect(
        ReturnOverdueOverageCalc.resolveHourlyRate(
          rentalType: 'daily',
          pricePerHour: 10000,
          dailyOverageHourlyRate: 15000,
        ),
        15000,
      );

      expect(
        ReturnOverdueOverageCalc.resolveHourlyRate(
          rentalType: 'daily',
          pricePerHour: 10000,
          dailyOverageHourlyRate: null,
        ),
        isNull,
      );
    });

    test('monthly 반납지연 — daily_overage_hourly_rate (예약기간 초과일요금과 별개)', () {
      expect(
        ReturnOverdueOverageCalc.resolveHourlyRate(
          rentalType: 'monthly',
          pricePerHour: 10000,
          dailyOverageHourlyRate: 12000,
        ),
        12000,
      );
    });
  });

  group('예약 52 (BYD 아토3, hourly) 반납 시뮬레이션', () {
    test('2시간 10분 지연 → 3시간 × ₩10,000 = ₩30,000', () {
      const pricePerHour = 10000;
      const dailyOverageHourlyRate = 10000; // 임시값 — hourly는 무시되어야 함

      final rate = ReturnOverdueOverageCalc.resolveHourlyRate(
        rentalType: 'hourly',
        pricePerHour: pricePerHour,
        dailyOverageHourlyRate: dailyOverageHourlyRate,
      );
      expect(rate, 10000);

      final scheduledEnd = DateTime(2026, 6, 5, 14, 0);
      final returnedAt = scheduledEnd.add(const Duration(hours: 2, minutes: 10));

      final result = ReturnOverdueOverageCalc.calc(
        scheduledEnd: scheduledEnd,
        returnedAt: returnedAt,
        hourlyRate: rate,
      );

      expect(result.billedHours, 3);
      expect(result.amount, 30000);
      expect(result.rateMissing, isFalse);
    });

    test('daily_overage만 있고 hourly_rate 없을 때 hourly 예약은 rateMissing', () {
      final rate = ReturnOverdueOverageCalc.resolveHourlyRate(
        rentalType: 'hourly',
        pricePerHour: null,
        dailyOverageHourlyRate: 10000,
      );
      expect(rate, isNull);

      final scheduledEnd = DateTime(2026, 6, 5, 14, 0);
      final returnedAt = scheduledEnd.add(const Duration(hours: 1));

      final result = ReturnOverdueOverageCalc.calc(
        scheduledEnd: scheduledEnd,
        returnedAt: returnedAt,
        hourlyRate: rate,
      );

      expect(result.billedHours, 1);
      expect(result.amount, 0);
      expect(result.rateMissing, isTrue);
    });
  });
}
