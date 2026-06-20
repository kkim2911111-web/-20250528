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
  });
}
