import 'package:intl/intl.dart';

/// 예약번호·대여 시각 UI 표시 공통 유틸

final _numericReservationId = RegExp(r'^\d+$');
final _danjiOrderId = RegExp(r'^danji_\d+(_|$)');

bool isNumericReservationId(String? value) {
  final s = value?.trim() ?? '';
  return s.isNotEmpty && _numericReservationId.hasMatch(s);
}

bool isDanjiOrderId(String? value) {
  final s = value?.trim() ?? '';
  return s.isNotEmpty && _danjiOrderId.hasMatch(s);
}

/// 이용내역·관리자 카드 공통 — #숫자(또는 UUID 앞 8자리)
String? resolveReservationDisplayToken(
  String rawId, {
  String? paymentReservationId,
  String? orderId,
}) {
  for (final candidate in [rawId, paymentReservationId, orderId]) {
    final s = candidate?.trim() ?? '';
    if (s.isEmpty || isDanjiOrderId(s)) continue;
    if (_numericReservationId.hasMatch(s)) return s;
  }

  for (final candidate in [rawId, paymentReservationId, orderId]) {
    final s = candidate?.trim() ?? '';
    if (s.isEmpty || isDanjiOrderId(s)) continue;
    final compact = s.replaceAll('-', '').toLowerCase();
    if (RegExp(r'^[0-9a-f]{8,}$').hasMatch(compact)) {
      return compact.substring(0, 8);
    }
  }

  return null;
}

String formatReservationDisplayId(
  String rawId, {
  String? paymentReservationId,
  String? orderId,
}) {
  final token = resolveReservationDisplayToken(
    rawId,
    paymentReservationId: paymentReservationId,
    orderId: orderId,
  );
  if (token == null || token.isEmpty) return '—';
  return '#$token';
}

/// 신규 reservation_number 우선, 없으면 레거시 #id
String resolveReservationNumberLabel({
  String? reservationNumber,
  required String rawId,
  String? paymentReservationId,
  String? orderId,
}) {
  final number = reservationNumber?.trim();
  if (number != null && number.isNotEmpty) return number;
  return formatReservationDisplayId(
    rawId,
    paymentReservationId: paymentReservationId,
    orderId: orderId,
  );
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

DateTime? scheduledStartFromMap(Map<String, dynamic> row) {
  return parseReservationDate(row['start_at'] ?? row['start_time']);
}

DateTime? scheduledEndFromMap(Map<String, dynamic> row) {
  return parseReservationDate(row['end_at'] ?? row['end_time']);
}

/// 관리자 검수 완료 시각 — DB 컬럼 없으면 completed 시 updated_at
DateTime? resolveReturnCompletedAt({
  required String? status,
  DateTime? returnCompletedAt,
  DateTime? updatedAt,
}) {
  if (returnCompletedAt != null) return returnCompletedAt;
  if (status == 'completed') return updatedAt;
  return null;
}

String formatOptionalDateTime(DateFormat formatter, DateTime? value) {
  if (value == null) return '-';
  return formatter.format(value.toLocal());
}

String formatScheduledPeriod({
  required DateFormat formatter,
  DateTime? startAt,
  DateTime? endAt,
}) {
  return formatRentalPeriod(formatter: formatter, start: startAt, end: endAt);
}

/// 이용내역 카드 — 예약/대여 시각 (KST, 동일일은 HH:mm)
String? formatHistoryTimeRangeLabel({
  required String prefix,
  DateTime? start,
  DateTime? end,
  DateFormat? fullFormatter,
}) {
  if (end == null) return null;
  final endLocal = end.toLocal();
  if (start == null) {
    final formatter = fullFormatter ?? DateFormat('yyyy-MM-dd HH:mm');
    return '$prefix - ~ ${formatter.format(endLocal)}';
  }
  final startLocal = start.toLocal();
  final startDay = DateTime(
    startLocal.year,
    startLocal.month,
    startLocal.day,
  );
  final endDay = DateTime(endLocal.year, endLocal.month, endLocal.day);
  if (startDay == endDay) {
    final time = DateFormat('HH:mm');
    return '$prefix ${time.format(startLocal)} ~ ${time.format(endLocal)}';
  }
  final formatter = fullFormatter ?? DateFormat('yyyy-MM-dd HH:mm');
  return '$prefix ${formatter.format(startLocal)} ~ ${formatter.format(endLocal)}';
}

/// 예약·결제 완료 — 차량명 · 기간 (예: 카니발9 · 1개월 5일)
String? formatBookingSummaryLine({
  String? vehicleName,
  String? durationLabel,
}) {
  final name = vehicleName?.trim();
  final duration = durationLabel?.trim();
  if (name != null && name.isNotEmpty && duration != null && duration.isNotEmpty) {
    return '$name · $duration';
  }
  if (name != null && name.isNotEmpty) return name;
  if (duration != null && duration.isNotEmpty) return duration;
  return null;
}

/// 예약/대여/반납/검수 시각 표시 모드
enum ReservationTimesMode {
  /// 이용자 상세 — 대여 시작·반납은 값이 있을 때만
  residentDetail,

  /// 관리자 목록/상세 — 대여 시작·반납은 값이 있을 때만
  admin,

  /// 반납 검수 대기 — 세 항목 항상 표시, 노쇼는 미대여
  inspectionPending,

  /// 반납 검수 완료 — 검수 완료 시각 포함
  inspectionCompleted,
}
