import '../models/super_admin_models.dart';

/// 전체 예약 목록 정렬·필터 기준 시각 (취소 건은 취소일, 그 외 대여 시작일)
DateTime? superAdminReservationSortAxis(SuperAdminReservation reservation) {
  final status = reservation.status.trim().toLowerCase();
  if (status == 'cancelled') {
    return reservation.cancelledAt ?? reservation.startAt;
  }
  return reservation.startAt;
}

/// 대여 날짜순 정렬 (최신 우선). 취소 건은 취소일자 기준으로 같은 축에 배치.
void sortSuperAdminReservationsByRentalAxis(List<SuperAdminReservation> list) {
  list.sort((a, b) {
    final aAxis = superAdminReservationSortAxis(a);
    final bAxis = superAdminReservationSortAxis(b);
    if (aAxis == null && bAxis == null) return 0;
    if (aAxis == null) return 1;
    if (bAxis == null) return -1;
    return bAxis.compareTo(aAxis);
  });
}

bool superAdminReservationMatchesMonth({
  required SuperAdminReservation reservation,
  required int year,
  required int month,
  DateTime? filterDate,
}) {
  final axis = superAdminReservationSortAxis(reservation);
  if (axis == null) return filterDate == null;

  final local = axis.toLocal();
  if (local.year != year || local.month != month) return false;
  if (filterDate != null) {
    return local.year == filterDate.year &&
        local.month == filterDate.month &&
        local.day == filterDate.day;
  }
  return true;
}
