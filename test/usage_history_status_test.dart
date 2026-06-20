import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/models/reservation.dart';

Reservation _sample({
  required String status,
  DateTime? endAt,
  bool isOverdue = false,
}) {
  return Reservation(
    id: 'r1',
    userId: 'u1',
    vehicleId: 'v1',
    totalPrice: 10000,
    status: status,
    endAt: endAt,
    isOverdue: isOverdue,
  );
}

void main() {
  group('이용내역 status/is_overdue 분류', () {
    final pastEnd = DateTime.now().subtract(const Duration(hours: 2));

    test('in_use + is_overdue — 이용완료 탭 제외, 반납지연 뱃지', () {
      final r = _sample(status: 'in_use', endAt: pastEnd, isOverdue: true);

      expect(r.isEffectivelyFinished, isFalse);
      expect(r.isInUsageHistory, isFalse);
      expect(r.appearsInUsageHistoryScreen, isTrue);
      expect(r.isUsageHistoryCompleted, isFalse);
      expect(r.isReturnOverdue, isTrue);
      expect(r.displayStatusLabel, '반납지연중');
    });

    test('in_use + end_at 경과(미반납) — is_overdue 없어도 반납지연', () {
      final r = _sample(status: 'in_use', endAt: pastEnd);

      expect(r.isReturnOverdue, isTrue);
      expect(r.displayStatusLabel, '반납지연중');
    });

    test('in_use + !is_overdue — 이용내역 제외, 대여 중', () {
      final futureEnd = DateTime.now().add(const Duration(hours: 2));
      final r = _sample(status: 'in_use', endAt: futureEnd);

      expect(r.isEffectivelyFinished, isFalse);
      expect(r.appearsInUsageHistoryScreen, isFalse);
      expect(r.isUsageHistoryCompleted, isFalse);
      expect(r.displayStatusLabel, '대여 중');
    });

    test('completed — 이용완료 탭 포함', () {
      final r = _sample(status: 'completed', endAt: pastEnd);

      expect(r.isUsageHistoryCompleted, isTrue);
      expect(r.displayStatusLabel, '이용 완료');
    });

    test('confirmed + end_at 경과 — 전체 탭만, 이용 종료 뱃지', () {
      final r = _sample(status: 'confirmed', endAt: pastEnd);

      expect(r.isEffectivelyFinished, isTrue);
      expect(r.appearsInUsageHistoryScreen, isTrue);
      expect(r.isUsageHistoryCompleted, isFalse);
      expect(r.displayStatusLabel, '이용 종료');
    });

    test('cancelled — 취소 탭만', () {
      final r = _sample(status: 'cancelled', endAt: pastEnd);

      expect(r.isUsageHistoryCompleted, isFalse);
      expect(r.displayStatusLabel, '예약 취소');
    });
  });
}
