/// 예약 겹침 — DB `reservation_effective_end` / `reservations_overlap_exists`와 동일
class ReservationOverlapLogic {
  static const postReturnBookingBuffer = Duration(minutes: 30);
  static final DateTime inUseOpenEnd = DateTime.utc(9999, 12, 31, 23, 59, 59);

  static DateTime _withBookingBuffer(DateTime end) =>
      end.add(postReturnBookingBuffer);

  static DateTime effectiveEnd({
    required String status,
    required DateTime? scheduledEnd,
    DateTime? actualEndAt,
    DateTime? returnedAt,
  }) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'in_use') {
      final end = scheduledEnd ?? actualEndAt ?? returnedAt;
      if (end == null) return inUseOpenEnd;
      return _withBookingBuffer(end);
    }
    if (normalized == 'returned' ||
        normalized == 'completed' ||
        normalized == 'cancelled') {
      final raw = actualEndAt ?? returnedAt ?? scheduledEnd ?? DateTime.utc(1970);
      return _withBookingBuffer(raw);
    }
    if (scheduledEnd == null) return DateTime.utc(1970);
    return _withBookingBuffer(scheduledEnd);
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
