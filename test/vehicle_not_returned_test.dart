import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/models/reservation.dart';
import 'package:danjicar_app/utils/cancel_reason.dart';
import 'package:danjicar_app/utils/reservation_status_badge.dart';

void main() {
  group('차량미회수 vs 노쇼 구분', () {
    Reservation victim({
      required String status,
      bool isNoShow = false,
      String? cancelReason,
      int refundAmount = 0,
      int totalPrice = 10000,
    }) {
      return Reservation.fromMap({
        'id': 'b',
        'user_id': 'user-b',
        'vehicle_id': '23',
        'start_time': '2026-06-20T09:00:00Z',
        'end_time': '2026-06-20T10:00:00Z',
        'total_price': totalPrice,
        'status': status,
        'is_no_show': isNoShow,
        if (cancelReason != null) 'cancel_reason': cancelReason,
        'refund_amount': refundAmount,
      });
    }

    test('앞 예약 미반납 — cancelled + vehicle_not_returned, 노쇼 아님', () {
      final b = victim(
        status: 'cancelled',
        cancelReason: CancelReasonCode.vehicleNotReturned,
        refundAmount: 10000,
      );

      expect(b.isNoShow, isFalse);
      expect(b.isVehicleNotReturned, isTrue);
      expect(b.displayStatusLabel, vehicleNotReturnedStatusBadgeLabel);
    });

    test('진짜 노쇼 — completed + is_no_show', () {
      final b = victim(
        status: 'completed',
        isNoShow: true,
      );

      expect(b.isNoShow, isTrue);
      expect(b.isVehicleNotReturned, isFalse);
      expect(b.displayStatusLabel, '노쇼완료');
    });

    test('뱃지 스타일 — 이용불가 환불', () {
      final style = resolveReservationStatusStyle(
        status: 'cancelled',
        isVehicleNotReturned: true,
      );
      expect(style.label, vehicleNotReturnedStatusBadgeLabel);
    });

    test('전액환불 뱃지 조건 — paid=refund', () {
      final b = victim(
        status: 'cancelled',
        cancelReason: CancelReasonCode.vehicleNotReturned,
        refundAmount: 10000,
        totalPrice: 10000,
      );
      expect(b.refundAmount, b.paidAmount);
      expect(b.isVehicleNotReturned, isTrue);
    });
  });

  group('has_blocking_in_use 시나리오 (시간 순서)', () {
    test('B 종료 경과 + A in_use 미반납이면 B는 노쇼 라벨이 아님', () {
      // A: 18:00~19:00 in_use, B: 19:00~20:00 confirmed 종료 경과
      // DB cron 처리 후 기대 상태를 Dart 모델로 검증
      final processedB = Reservation.fromMap({
        'id': 'res-b',
        'user_id': 'user-b',
        'vehicle_id': '23',
        'start_time': '2026-06-20T10:00:00Z',
        'end_time': '2026-06-20T11:00:00Z',
        'total_price': 10000,
        'status': 'cancelled',
        'cancel_reason': 'vehicle_not_returned',
        'refund_amount': 10000,
        'is_no_show': false,
      });

      final processedNoShow = Reservation.fromMap({
        'id': 'res-c',
        'user_id': 'user-c',
        'vehicle_id': '23',
        'start_time': '2026-06-20T12:00:00Z',
        'end_time': '2026-06-20T13:00:00Z',
        'total_price': 8000,
        'status': 'completed',
        'is_no_show': true,
      });

      expect(processedB.isVehicleNotReturned, isTrue);
      expect(processedB.isNoShow, isFalse);
      expect(processedB.displayStatusLabel, '이용불가 환불');

      expect(processedNoShow.isNoShow, isTrue);
      expect(processedNoShow.isVehicleNotReturned, isFalse);
      expect(processedNoShow.displayStatusLabel, '노쇼완료');
    });
  });
}
