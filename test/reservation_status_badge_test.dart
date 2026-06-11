import 'package:danjicar_app/utils/reservation_status_badge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveReservationStatusStyle', () {
    test('cancelled — 취소', () {
      expect(
        resolveReservationStatusStyle(status: 'cancelled').label,
        '취소',
      );
    });

    test('confirmed — 예약확정', () {
      expect(
        resolveReservationStatusStyle(status: 'confirmed').label,
        '예약확정',
      );
    });

    test('completed — 완료', () {
      expect(
        resolveReservationStatusStyle(status: 'completed').label,
        '완료',
      );
    });

    test('completed + isNoShow — 노쇼', () {
      expect(
        resolveReservationStatusStyle(
          status: 'completed',
          isNoShow: true,
        ).label,
        '노쇼',
      );
    });

    test('in_use — 이용중', () {
      expect(
        resolveReservationStatusStyle(status: 'in_use').label,
        '이용중',
      );
    });
  });
}
