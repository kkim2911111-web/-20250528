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

  /// 홈 — in_use 최우선, 없으면 임박 예약
  Reservation? get homePrimary {
    final inUse = [
      ...operating,
      ...waiting,
    ].where((r) => r.status == 'in_use').toList();
    if (inUse.isNotEmpty) {
      inUse.sort((a, b) => a.sortByStart.compareTo(b.sortByStart));
      return inUse.first;
    }
    return soonestUpcoming;
  }

  /// 시작 시각 기준 가장 임박한 예약 (운행·대기 통합, 종료된 것 제외)
  Reservation? get soonestUpcoming {
    if (operating.isNotEmpty) {
      final sorted = [...operating]..sort(_compareHomePrimary);
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

  static int _compareHomePrimary(Reservation a, Reservation b) {
    final aInUse = a.status == 'in_use';
    final bInUse = b.status == 'in_use';
    if (aInUse && !bInUse) return -1;
    if (bInUse && !aInUse) return 1;
    return a.sortByStart.compareTo(b.sortByStart);
  }
}
