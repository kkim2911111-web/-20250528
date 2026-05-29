import '../models/reservation.dart';

class GroupedReservations {
  final List<Reservation> operating;
  final List<Reservation> waiting;
  final List<Reservation> finished;

  const GroupedReservations({
    required this.operating,
    required this.waiting,
    required this.finished,
  });

  bool get isEmpty =>
      operating.isEmpty && waiting.isEmpty && finished.isEmpty;

  /// 앞으로 이용·이용 중 예약 건수 (홈 "예약 N건")
  int get activeCount => operating.length + waiting.length;

  /// 홈 — 운행 중 우선, 없으면 시작 시각이 가장 빠른 **미래** 대기 예약
  Reservation? get mostImminent => soonestUpcoming;

  /// 시작 시각 기준 가장 임박한 예약 (운행·대기 통합, 종료된 것 제외)
  Reservation? get soonestUpcoming {
    if (operating.isNotEmpty) {
      final sorted = [...operating]
        ..sort((a, b) => a.sortByStart.compareTo(b.sortByStart));
      return sorted.first;
    }
    if (waiting.isEmpty) return null;

    final now = DateTime.now();
    for (final r in waiting) {
      final start = r.startAt;
      if (start == null || !start.isBefore(now)) return r;
    }
    return null;
  }
}
