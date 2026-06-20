/// 예약 겹침 — DB `reservation_effective_end` / `reservations_overlap_exists`와 동일
class ReservationOverlapLogic {
  static final DateTime inUseOpenEnd = DateTime.utc(9999, 12, 31, 23, 59, 59);

  static DateTime effectiveEnd({
    required String status,
    required DateTime? scheduledEnd,
    DateTime? actualEndAt,
    DateTime? returnedAt,
  }) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'in_use') {
      return inUseOpenEnd;
    }
    if (normalized == 'returned' ||
        normalized == 'completed' ||
        normalized == 'cancelled') {
      return actualEndAt ?? returnedAt ?? scheduledEnd ?? DateTime.utc(1970);
    }
    return scheduledEnd ?? DateTime.utc(1970);
  }

  static bool overlaps({
    required DateTime otherStart,
    required String otherStatus,
    required DateTime? otherScheduledEnd,
    DateTime? otherActualEndAt,
    DateTime? otherReturnedAt,
    required DateTime requestStart,
    required DateTime requestEnd,
  }) {
    if (!requestEnd.isAfter(requestStart)) return false;

    final otherEnd = effectiveEnd(
      status: otherStatus,
      scheduledEnd: otherScheduledEnd,
      actualEndAt: otherActualEndAt,
      returnedAt: otherReturnedAt,
    );

    return otherStart.isBefore(requestEnd) && otherEnd.isAfter(requestStart);
  }
}
