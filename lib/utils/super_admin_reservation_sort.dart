import 'package:intl/intl.dart';

import '../models/super_admin_models.dart';

final _axisDateTime = DateFormat('M/d HH:mm');
final _axisDate = DateFormat('M/d');

/// 전체 예약 목록 정렬·필터 기준 시각 (취소 건은 취소일, 그 외 대여 시작일)
DateTime? superAdminReservationSortAxis(SuperAdminReservation reservation) {
  final status = reservation.status.trim().toLowerCase();
  if (status == 'cancelled') {
    return reservation.cancelledAt ?? reservation.startAt;
  }
  return reservation.startAt;
}

bool superAdminReservationIsCancelled(SuperAdminReservation reservation) =>
    reservation.status.trim().toLowerCase() == 'cancelled';

/// 카드 기준일 — 일반: 대여 시작, 취소: "M/d 취소"
String superAdminReservationAxisLabel(SuperAdminReservation reservation) {
  if (superAdminReservationIsCancelled(reservation)) {
    final cancelled = reservation.cancelledAt ?? reservation.startAt;
    if (cancelled == null) return '취소일 미등록';
    return '${_axisDate.format(cancelled.toLocal())} 취소';
  }
  final start = reservation.startAt;
  if (start == null) return '—';
  return _axisDateTime.format(start.toLocal());
}

/// 필터 없음: 기준일 내림차순 · 날짜 필터: 해당 일 시간순 오름차순
void sortSuperAdminReservations(
  List<SuperAdminReservation> list, {
  DateTime? filterDate,
}) {
  final ascending = filterDate != null;
  list.sort((a, b) {
    final aAxis = superAdminReservationSortAxis(a);
    final bAxis = superAdminReservationSortAxis(b);
    if (aAxis == null && bAxis == null) return 0;
    if (aAxis == null) return 1;
    if (bAxis == null) return -1;
    return ascending ? aAxis.compareTo(bAxis) : bAxis.compareTo(aAxis);
  });
}

/// @deprecated [sortSuperAdminReservations] 사용
void sortSuperAdminReservationsByRentalAxis(List<SuperAdminReservation> list) {
  sortSuperAdminReservations(list);
}

String superAdminReservationSortHint({DateTime? filterDate}) {
  if (filterDate != null) {
    return '${DateFormat('yyyy-MM-dd').format(filterDate)} · 시간순';
  }
  return '대여일 최신순 (취소 건은 취소일 기준)';
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
