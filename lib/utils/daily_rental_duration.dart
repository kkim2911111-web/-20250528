/// 일 렌트 기간 — 24h 블록 + 초과 분(실제) / 초과 시간(올림 청구)
class DailyRentalDurationSplit {
  final int fullDays;
  final int overageMinutes;
  final int billedOverageHours;

  const DailyRentalDurationSplit({
    required this.fullDays,
    required this.overageMinutes,
    required this.billedOverageHours,
  });

  static const minutesPerDay = 24 * 60;

  static DailyRentalDurationSplit fromInterval({
    required DateTime start,
    required DateTime end,
  }) {
    if (!end.isAfter(start)) {
      return const DailyRentalDurationSplit(
        fullDays: 0,
        overageMinutes: 0,
        billedOverageHours: 0,
      );
    }

    final totalMinutes = end.difference(start).inMinutes;
    final fullDays = totalMinutes ~/ minutesPerDay;
    final overageMinutes = totalMinutes - fullDays * minutesPerDay;
    final billedOverageHours = overageMinutes > 0
        ? (overageMinutes + 59) ~/ 60
        : 0;

    return DailyRentalDurationSplit(
      fullDays: fullDays,
      overageMinutes: overageMinutes,
      billedOverageHours: billedOverageHours,
    );
  }

  bool get hasOverage => overageMinutes > 0;

  String formatLabel() {
    if (fullDays <= 0 && overageMinutes <= 0) return '';

    final parts = <String>[];
    if (fullDays > 0) {
      parts.add('$fullDays일');
    }
    if (overageMinutes > 0) {
      final hours = overageMinutes ~/ 60;
      final minutes = overageMinutes % 60;
      if (hours > 0) parts.add('$hours시간');
      if (minutes > 0) parts.add('$minutes분');
    }
    return parts.join(' ');
  }
}
