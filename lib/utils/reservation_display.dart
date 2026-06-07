import 'package:intl/intl.dart';

/// 예약번호·대여 시각 UI 표시 공통 유틸

String formatReservationDisplayId(
  String rawId, {
  String? paymentReservationId,
  String? orderId,
}) {
  for (final candidate in [rawId, paymentReservationId, orderId]) {
    final s = candidate?.trim() ?? '';
    if (s.isEmpty) continue;
    if (RegExp(r'^\d+$').hasMatch(s)) return '#$s';
  }
  return '#$rawId';
}

DateTime? parseReservationDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  return DateTime.tryParse(value.toString())?.toLocal();
}

/// 실제 대여 시작 시각 우선 (미대여 시 예약 시작 시각)
DateTime? resolveRentalStartDisplay({
  DateTime? rentalStartedAt,
  DateTime? scheduledStartAt,
}) {
  return rentalStartedAt ?? scheduledStartAt;
}

/// 실제 반납 시각 우선
DateTime? resolveRentalEndDisplay({
  DateTime? returnedAt,
  DateTime? actualEndAt,
  DateTime? scheduledEndAt,
}) {
  return returnedAt ?? actualEndAt ?? scheduledEndAt;
}

DateTime? displayRentalStartFromMap(Map<String, dynamic> row) {
  return resolveRentalStartDisplay(
    rentalStartedAt: parseReservationDate(row['rental_started_at']),
    scheduledStartAt: parseReservationDate(row['start_at'] ?? row['start_time']),
  );
}

DateTime? displayRentalEndFromMap(Map<String, dynamic> row) {
  return resolveRentalEndDisplay(
    returnedAt: parseReservationDate(row['returned_at']),
    actualEndAt: parseReservationDate(row['actual_end_at']),
    scheduledEndAt: parseReservationDate(row['end_at'] ?? row['end_time']),
  );
}

String formatRentalPeriod({
  required DateFormat formatter,
  DateTime? start,
  DateTime? end,
}) {
  if (start == null && end == null) return '-';
  final s = start != null ? formatter.format(start) : '-';
  final e = end != null ? formatter.format(end) : '-';
  return '$s ~ $e';
}
