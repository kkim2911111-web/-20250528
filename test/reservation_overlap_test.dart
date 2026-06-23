import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/utils/reservation_overlap.dart';

void main() {
  group('in_use 미반납 겹침', () {
    test('in_use — end_at+30분 이전은 겹침, 이후는 예약 가능', () {
      final scheduledEnd = DateTime.utc(2026, 6, 20, 5, 0); // 14:00 KST
      final otherStart = DateTime.utc(2026, 6, 20, 4, 0); // 13:00 KST
      final bufferedEnd = scheduledEnd.add(
        ReservationOverlapLogic.postReturnBookingBuffer,
      );

      expect(
        ReservationOverlapLogic.effectiveEnd(
          status: 'in_use',
          scheduledEnd: scheduledEnd,
        ),
        bufferedEnd,
      );

      // 14:00 시작 — 버퍼 안이라 불가
      expect(
        ReservationOverlapLogic.overlaps(
          otherStart: otherStart,
          otherStatus: 'in_use',
          otherScheduledEnd: scheduledEnd,
          requestStart: scheduledEnd,
          requestEnd: scheduledEnd.add(const Duration(hours: 1)),
        ),
        isTrue,
      );

      // 14:30 시작 — 버퍼 이후라 가능
      expect(
        ReservationOverlapLogic.overlaps(
          otherStart: otherStart,
          otherStatus: 'in_use',
          otherScheduledEnd: scheduledEnd,
          requestStart: bufferedEnd,
          requestEnd: bufferedEnd.add(const Duration(hours: 1)),
        ),
        isFalse,
      );
    });

    test('confirmed는 end_at+30분 버퍼 이후면 겹치지 않음', () {
      final scheduledEnd = DateTime.utc(2026, 6, 20, 11, 0);
      final otherStart = DateTime.utc(2026, 6, 20, 10, 0);
      final requestStart = DateTime.utc(2026, 6, 20, 14, 0);
      final requestEnd = DateTime.utc(2026, 6, 20, 15, 0);

      expect(
        ReservationOverlapLogic.overlaps(
          otherStart: otherStart,
          otherStatus: 'confirmed',
          otherScheduledEnd: scheduledEnd,
          requestStart: requestStart,
          requestEnd: requestEnd,
        ),
        isFalse,
      );
    });

    test('in_use 시작 전 시간대는 예약 가능', () {
      final scheduledEnd = DateTime.utc(2026, 6, 20, 11, 0);
      final otherStart = DateTime.utc(2026, 6, 20, 10, 0);
      final requestStart = DateTime.utc(2026, 6, 20, 8, 0);
      final requestEnd = DateTime.utc(2026, 6, 20, 9, 0);

      expect(
        ReservationOverlapLogic.overlaps(
          otherStart: otherStart,
          otherStatus: 'in_use',
          otherScheduledEnd: scheduledEnd,
          requestStart: requestStart,
          requestEnd: requestEnd,
        ),
        isFalse,
      );
    });

    test('순차 confirmed — 30분 버퍼로 19:00 시작은 겹침', () {
      final firstStart = DateTime.utc(2026, 6, 20, 9, 0); // 18:00 KST
      final firstEnd = DateTime.utc(2026, 6, 20, 10, 0); // 19:00 KST
      final secondStart = DateTime.utc(2026, 6, 20, 10, 0); // 19:00 KST
      final secondEnd = DateTime.utc(2026, 6, 20, 11, 0); // 20:00 KST

      expect(
        ReservationOverlapLogic.overlaps(
          otherStart: firstStart,
          otherStatus: 'confirmed',
          otherScheduledEnd: firstEnd,
          requestStart: secondStart,
          requestEnd: secondEnd,
        ),
        isTrue,
      );

      final bufferedStart = DateTime.utc(2026, 6, 20, 10, 30); // 19:30 KST
      expect(
        ReservationOverlapLogic.overlaps(
          otherStart: firstStart,
          otherStatus: 'confirmed',
          otherScheduledEnd: firstEnd,
          requestStart: bufferedStart,
          requestEnd: secondEnd,
        ),
        isFalse,
      );
    });
  });
}
