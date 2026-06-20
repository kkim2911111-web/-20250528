import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/utils/daily_rental_duration.dart';

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
}
