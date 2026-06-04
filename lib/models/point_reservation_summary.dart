/// 포인트 내역 — 예약 기준 차량·이용시간 표시용
class PointReservationSummary {
  final String vehicleName;
  final int durationHours;

  const PointReservationSummary({
    required this.vehicleName,
    required this.durationHours,
  });

  String get lineLabel {
    if (durationHours >= 1) {
      return '$vehicleName · ${durationHours}시간';
    }
    return vehicleName;
  }
}
