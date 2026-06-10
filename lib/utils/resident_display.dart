import 'package:intl/intl.dart';

abstract final class ResidentDisplay {
  static final _day = DateFormat('yyyy.MM.dd');

  static String formatDay(DateTime? value) {
    if (value == null) return '-';
    return _day.format(value.toLocal());
  }

  static String joinAndRentalLine({
    required DateTime? joinedAt,
    required DateTime? lastRentalAt,
  }) {
    final join = '가입 ${formatDay(joinedAt)}';
    if (lastRentalAt == null) {
      return '$join · 대여 이력 없음';
    }
    return '$join · 최근 대여 ${formatDay(lastRentalAt)}';
  }

  static String? formatLicenseExpiry(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed != null) return formatDay(parsed);
    return raw.trim();
  }
}
