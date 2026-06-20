/// 반납 지연 초과 이용 요금 — DB `calc_return_overdue_overage` / `resolve_return_overdue_hourly_rate`와 동일 규칙
class ReturnOverdueOverageResult {
  final int billedHours;
  final int amount;
  final bool rateMissing;

  const ReturnOverdueOverageResult({
    required this.billedHours,
    required this.amount,
    required this.rateMissing,
  });
}

class ReturnOverdueOverageCalc {
  /// 예약 `rental_type`에 맞는 반납 지연 시간당 요율
  static int? resolveHourlyRate({
    required String? rentalType,
    int? hourlyRate,
    int? pricePerHour,
    int? dailyOverageHourlyRate,
  }) {
    switch ((rentalType ?? 'hourly').trim().toLowerCase()) {
      case 'hourly':
        final rate = hourlyRate ?? pricePerHour;
        if (rate == null || rate <= 0) return null;
        return rate;
      case 'daily':
      case 'monthly':
        if (dailyOverageHourlyRate == null || dailyOverageHourlyRate <= 0) {
          return null;
        }
        return dailyOverageHourlyRate;
      default:
        return null;
    }
  }

  static ReturnOverdueOverageResult calc({
    required DateTime scheduledEnd,
    required DateTime returnedAt,
    required int? hourlyRate,
  }) {
    if (!returnedAt.isAfter(scheduledEnd)) {
      return const ReturnOverdueOverageResult(
        billedHours: 0,
        amount: 0,
        rateMissing: false,
      );
    }

    final lateMinutes = returnedAt.difference(scheduledEnd).inMinutes;
    final billedHours = lateMinutes > 0 ? (lateMinutes + 59) ~/ 60 : 0;

    if (hourlyRate == null || hourlyRate <= 0) {
      return ReturnOverdueOverageResult(
        billedHours: billedHours,
        amount: 0,
        rateMissing: true,
      );
    }

    return ReturnOverdueOverageResult(
      billedHours: billedHours,
      amount: billedHours * hourlyRate,
      rateMissing: false,
    );
  }
}
