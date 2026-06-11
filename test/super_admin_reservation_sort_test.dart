import 'package:danjicar_app/models/super_admin_models.dart';
import 'package:danjicar_app/utils/super_admin_reservation_sort.dart';
import 'package:flutter_test/flutter_test.dart';

SuperAdminReservation _reservation({
  required String id,
  required String status,
  DateTime? startAt,
  DateTime? cancelledAt,
}) {
  return SuperAdminReservation(
    id: id,
    complexId: 'c1',
    complexName: '단지',
    vehicleId: 'v1',
    vehicleName: '차량',
    renterName: '홍길동',
    renterPhone: '010',
    status: status,
    startAt: startAt,
    cancelledAt: cancelledAt,
  );
}

void main() {
  test('sortSuperAdminReservations desc without date filter', () {
    final list = [
      _reservation(
        id: 'active',
        status: 'confirmed',
        startAt: DateTime(2026, 6, 20),
      ),
      _reservation(
        id: 'cancelled',
        status: 'cancelled',
        startAt: DateTime(2026, 6, 25),
        cancelledAt: DateTime(2026, 6, 10),
      ),
      _reservation(
        id: 'later-cancel',
        status: 'cancelled',
        startAt: DateTime(2026, 6, 1),
        cancelledAt: DateTime(2026, 6, 15),
      ),
    ];

    sortSuperAdminReservations(list);

    expect(list.map((r) => r.id).toList(), [
      'active',
      'later-cancel',
      'cancelled',
    ]);
  });

  test('sortSuperAdminReservations asc with date filter', () {
    final filterDay = DateTime(2026, 6, 11);
    final list = [
      _reservation(
        id: 'afternoon',
        status: 'confirmed',
        startAt: DateTime(2026, 6, 11, 15),
      ),
      _reservation(
        id: 'morning',
        status: 'confirmed',
        startAt: DateTime(2026, 6, 11, 9),
      ),
      _reservation(
        id: 'cancel-same-day',
        status: 'cancelled',
        startAt: DateTime(2026, 6, 20),
        cancelledAt: DateTime(2026, 6, 11, 12),
      ),
    ];

    sortSuperAdminReservations(list, filterDate: filterDay);

    expect(list.map((r) => r.id).toList(), [
      'morning',
      'cancel-same-day',
      'afternoon',
    ]);
  });

  test('superAdminReservationAxisLabel formats start and cancel', () {
    final active = _reservation(
      id: 'a',
      status: 'confirmed',
      startAt: DateTime(2026, 6, 13, 10),
    );
    final cancelled = _reservation(
      id: 'c',
      status: 'cancelled',
      startAt: DateTime(2026, 6, 20),
      cancelledAt: DateTime(2026, 6, 11),
    );

    expect(superAdminReservationAxisLabel(active), '6/13 10:00');
    expect(superAdminReservationAxisLabel(cancelled), '6/11 취소');
  });

  test('superAdminReservationSortHint reflects filter state', () {
    expect(
      superAdminReservationSortHint(),
      '대여일 최신순 (취소 건은 취소일 기준)',
    );
    expect(
      superAdminReservationSortHint(
        filterDate: DateTime(2026, 6, 11),
      ),
      '2026-06-11 · 시간순',
    );
  });

  test('superAdminReservationMatchesMonth uses cancel date for cancelled', () {
    final cancelled = _reservation(
      id: 'c1',
      status: 'cancelled',
      startAt: DateTime(2026, 5, 1),
      cancelledAt: DateTime(2026, 6, 12),
    );

    expect(
      superAdminReservationMatchesMonth(
        reservation: cancelled,
        year: 2026,
        month: 6,
      ),
      isTrue,
    );
    expect(
      superAdminReservationMatchesMonth(
        reservation: cancelled,
        year: 2026,
        month: 5,
      ),
      isFalse,
    );
  });
}
