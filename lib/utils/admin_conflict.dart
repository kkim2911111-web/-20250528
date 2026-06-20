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

const _activeConflictStatuses = {'pending', 'confirmed', 'in_use'};

/// 동일 차량 겹침·연속 예약 충돌 위험 (예약 확정 즉시, in_use 한정 아님)
bool isBackToBackConflictRow(Map<String, dynamic> row) {
  if (row['is_conflict_risk'] == true) return true;

  final status = adminReservationStatus(row);
  if (!_activeConflictStatuses.contains(status)) return false;
  if (isNoShowSuspectRow(row)) return false;

  return parseAdminReservationDate(row['next_start_at']) != null;
}

int countBackToBackConflicts(List<Map<String, dynamic>> rows) =>
    rows.where(isBackToBackConflictRow).length;
