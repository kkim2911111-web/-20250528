import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/utils/reservation_overlap.dart';

void main() {
  group('in_use 미반납 겹침', () {
    test('end_at 지났어도 in_use면 이후 시간대 예약 불가', () {
      final scheduledEnd = DateTime.utc(2026, 6, 20, 11, 0); // 20:00 KST
      final otherStart = DateTime.utc(2026, 6, 20, 10, 0); // 19:00 KST
      final requestStart = DateTime.utc(2026, 6, 20, 14, 0); // 23:00 KST
      final requestEnd = DateTime.utc(2026, 6, 20, 15, 0); // 00:00 KST

      expect(
        ReservationOverlapLogic.effectiveEnd(
          status: 'in_use',
          scheduledEnd: scheduledEnd,
        ),
        ReservationOverlapLogic.inUseOpenEnd,
      );

      expect(
        ReservationOverlapLogic.overlaps(
          otherStart: otherStart,
          otherStatus: 'in_use',
          otherScheduledEnd: scheduledEnd,
          requestStart: requestStart,
          requestEnd: requestEnd,
        ),
        isTrue,
      );
    });

    test('confirmed는 end_at 이후면 겹치지 않음', () {
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

    test('순차 confirmed 예약은 시간 겹치지 않음 (18:00~19:00 / 19:00~20:00)', () {
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
        isFalse,
      );

      // 18:00 예약이 in_use여도, 이미 잡힌 19:00 구간과는 RPC/앱 겹침 검사 대상이 아님
      // (신규 19:00 예약 시도만 in_use와 충돌 — 별도 케이스)
      expect(
        ReservationOverlapLogic.overlaps(
          otherStart: secondStart,
          otherStatus: 'confirmed',
          otherScheduledEnd: secondEnd,
          requestStart: firstStart,
          requestEnd: firstEnd,
        ),
        isFalse,
      );
    });
  });
}
