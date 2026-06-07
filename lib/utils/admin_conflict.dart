DateTime? parseAdminReservationDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  return DateTime.tryParse(value.toString())?.toLocal();
}

String adminReservationStatus(Map<String, dynamic> row) {
  final v = row['status'];
  if (v == null) return '';
  final s = v.toString().trim();
  return s.isEmpty ? '' : s.toLowerCase();
}

bool isNoShowSuspectRow(Map<String, dynamic> row) {
  if (adminReservationStatus(row) != 'confirmed') return false;
  final start = parseAdminReservationDate(row['start_at']);
  if (start == null) return false;
  return !start.isAfter(DateTime.now());
}

/// 반납 직후·근접 다음 예약 (종료 ±5분 ~ +30분)
bool isBackToBackConflictRow(Map<String, dynamic> row) {
  if (adminReservationStatus(row) != 'in_use') return false;
  if (isNoShowSuspectRow(row)) return false;

  final end = parseAdminReservationDate(row['end_at']);
  final nextStart = parseAdminReservationDate(row['next_start_at']);
  if (end == null || nextStart == null) return false;

  final endUtc = end.toUtc();
  final nextUtc = nextStart.toUtc();
  final lower = endUtc.subtract(const Duration(minutes: 5));
  final upper = endUtc.add(const Duration(minutes: 30));

  return !nextUtc.isBefore(lower) && !nextUtc.isAfter(upper);
}

int countBackToBackConflicts(List<Map<String, dynamic>> rows) =>
    rows.where(isBackToBackConflictRow).length;
