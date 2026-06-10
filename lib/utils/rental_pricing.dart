import '../models/vehicle.dart';

enum RentalType {
  hourly,
  daily,
  monthly;

  String get dbValue {
    switch (this) {
      case RentalType.hourly:
        return 'hourly';
      case RentalType.daily:
        return 'daily';
      case RentalType.monthly:
        return 'monthly';
    }
  }

  String get label {
    switch (this) {
      case RentalType.hourly:
        return '시간';
      case RentalType.daily:
        return '일';
      case RentalType.monthly:
        return '월';
    }
  }

  static RentalType? fromDb(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'hourly':
        return RentalType.hourly;
      case 'daily':
        return RentalType.daily;
      case 'monthly':
        return RentalType.monthly;
      default:
        return null;
    }
  }
}

class VehicleServiceType {
  static const sharing = 'sharing';
  static const rental = 'rental';
}

class RentalPricing {
  static const maxHourlyHours = 23;
  static const sharingMaxHours = 23;
  static const maxDailyDays = 29;
  static const maxMonthlyMonths = 11;
  static const dailyFromHourlyMultiplier = 20;
  static const monthlyFromDailyMultiplier = 25;
  static const hoursPerDayForComparison = 24;

  static List<RentalType> parseRentalTypes(dynamic raw) {
    if (raw is List) {
      final parsed = <RentalType>[];
      for (final item in raw) {
        final type = RentalType.fromDb(item?.toString());
        if (type != null && !parsed.contains(type)) {
          parsed.add(type);
        }
      }
      if (parsed.isNotEmpty) return parsed;
    }
    return const [RentalType.hourly];
  }

  static String serviceTypeFromRentalTypes(Set<RentalType> types) {
    if (types.contains(RentalType.daily) || types.contains(RentalType.monthly)) {
      return VehicleServiceType.rental;
    }
    return VehicleServiceType.sharing;
  }

  static String parseServiceType(
    dynamic raw, {
    Iterable<RentalType>? rentalTypes,
  }) {
    final value = raw?.toString().trim().toLowerCase();
    if (value == VehicleServiceType.sharing ||
        value == VehicleServiceType.rental) {
      return value!;
    }
    if (rentalTypes != null) {
      return serviceTypeFromRentalTypes(rentalTypes.toSet());
    }
    return VehicleServiceType.sharing;
  }

  static String? parseCarCategory(Map<String, dynamic> map) {
    final carType = map['car_type']?.toString().trim();
    if (carType != null && carType.isNotEmpty) return carType;

    final legacy = map['vehicle_type']?.toString().trim();
    if (legacy == null || legacy.isEmpty) {
      return _readLegacyCategory(map);
    }
    if (legacy == VehicleServiceType.sharing ||
        legacy == VehicleServiceType.rental) {
      return null;
    }
    return legacy;
  }

  static String? _readLegacyCategory(Map<String, dynamic> map) {
    for (final key in ['type', 'car_type']) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static String requiredServiceTypeForBooking({
    required RentalType rentalType,
    required int durationHours,
  }) {
    if (rentalType == RentalType.hourly && durationHours <= sharingMaxHours) {
      return VehicleServiceType.sharing;
    }
    return VehicleServiceType.rental;
  }

  static List<String> rentalTypesToDb(Iterable<RentalType> types) {
    final list = types.map((t) => t.dbValue).toList();
    if (list.isEmpty) return const ['hourly'];
    return list;
  }

  static int effectiveDailyPrice(Vehicle vehicle) {
    return vehicle.dailyPrice ?? vehicle.pricePerHour * dailyFromHourlyMultiplier;
  }

  static int effectiveMonthlyPrice(Vehicle vehicle) {
    return vehicle.monthlyPrice ??
        effectiveDailyPrice(vehicle) * monthlyFromDailyMultiplier;
  }

  static int previewDailyPrice(int hourlyPrice) =>
      hourlyPrice * dailyFromHourlyMultiplier;

  static int previewMonthlyPrice(int dailyPrice) =>
      dailyPrice * monthlyFromDailyMultiplier;

  /// 차량 카드·목록용 단가 표기 (예: ₩5,000/시간)
  static String unitPriceLabel(Vehicle vehicle, RentalType type) {
    switch (type) {
      case RentalType.hourly:
        return vehicle.priceLabel;
      case RentalType.daily:
        return '${_formatWon(effectiveDailyPrice(vehicle))}/일';
      case RentalType.monthly:
        return '${_formatWon(effectiveMonthlyPrice(vehicle))}/월';
    }
  }

  /// rental_types 기준 대표 단가 (시간 미지원 차량의 ₩0/h 방지)
  static RentalType representativeRentalType(Vehicle vehicle) {
    final types = vehicle.rentalTypes;
    if (types.contains(RentalType.monthly)) return RentalType.monthly;
    if (types.contains(RentalType.daily)) return RentalType.daily;
    return RentalType.hourly;
  }

  static String displayUnitPriceLabel(Vehicle vehicle, RentalType periodType) {
    final billingType = vehicle.supportsRentalType(periodType)
        ? periodType
        : representativeRentalType(vehicle);
    return unitPriceLabel(vehicle, billingType);
  }

  static String _formatWon(int amount) {
    final s = amount.toString();
    final buf = StringBuffer('₩');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static int calculatePrice(
    Vehicle vehicle,
    RentalType type, {
    required int hours,
    required int days,
    required int months,
  }) {
    switch (type) {
      case RentalType.hourly:
        return hours.clamp(0, maxHourlyHours) * vehicle.pricePerHour;
      case RentalType.daily:
        return days.clamp(0, maxDailyDays) * effectiveDailyPrice(vehicle);
      case RentalType.monthly:
        return months.clamp(0, maxMonthlyMonths) * effectiveMonthlyPrice(vehicle);
    }
  }

  /// 일/월 탭에서 취소선으로 표시할 비교 요금
  static int? comparisonStrikethroughPrice(
    Vehicle vehicle,
    RentalType type, {
    required int hours,
    required int days,
    required int months,
  }) {
    switch (type) {
      case RentalType.hourly:
        return null;
      case RentalType.daily:
        final compareHours = days * hoursPerDayForComparison;
        return compareHours * vehicle.pricePerHour;
      case RentalType.monthly:
        final compareDays = months * 30;
        return compareDays * effectiveDailyPrice(vehicle);
    }
  }

  static DateTime addMonths(DateTime start, int months) {
    var year = start.year;
    var month = start.month + months;
    while (month > 12) {
      year++;
      month -= 12;
    }
    while (month < 1) {
      year--;
      month += 12;
    }
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = start.day > lastDay ? lastDay : start.day;
    return DateTime(year, month, day, start.hour, start.minute, start.second);
  }

  static DateTime? buildEndTime(
    DateTime start,
    RentalType type, {
    required int endHour,
    required int days,
    required int months,
  }) {
    switch (type) {
      case RentalType.hourly:
        var end = DateTime(start.year, start.month, start.day, endHour);
        if (!end.isAfter(start)) {
          end = end.add(const Duration(days: 1));
        }
        return end;
      case RentalType.daily:
        return start.add(Duration(days: days));
      case RentalType.monthly:
        return addMonths(start, months);
    }
  }

  static String durationSummary(
    RentalType type, {
    required int hours,
    required int days,
    required int months,
  }) {
    switch (type) {
      case RentalType.hourly:
        return '${hours}시간';
      case RentalType.daily:
        return '${days}일';
      case RentalType.monthly:
        return '${months}개월';
    }
  }

  static bool isValidDuration(
    RentalType type, {
    required int hours,
    required int days,
    required int months,
  }) {
    switch (type) {
      case RentalType.hourly:
        return hours >= 1 && hours <= maxHourlyHours;
      case RentalType.daily:
        return days >= 1 && days <= maxDailyDays;
      case RentalType.monthly:
        return months >= 1 && months <= maxMonthlyMonths;
    }
  }

  /// 기간으로 rental_type 추론 — 24h 미만 hourly / 24h~30일 미만 daily / 30일+ monthly
  static RentalType inferRentalTypeFromInterval({
    required DateTime start,
    required DateTime end,
  }) {
    final seconds = end.difference(start).inSeconds;
    if (seconds < 86400) return RentalType.hourly;
    if (seconds < 30 * 86400) return RentalType.daily;
    return RentalType.monthly;
  }

  static int? inferHoursBetween(DateTime start, DateTime end) {
    final hours = end.difference(start).inHours;
    if (hours < 1 || hours > maxHourlyHours) return null;
    return hours;
  }

  static int? inferDaysBetween(DateTime start, DateTime end) {
    final days = end.difference(start).inDays;
    if (days < 1 || days > maxDailyDays) return null;
    return days;
  }

  static int? inferMonthsBetween(DateTime start, DateTime end) {
    for (var i = 1; i <= maxMonthlyMonths; i++) {
      if (addMonths(start, i) == end) return i;
    }
    return null;
  }

  /// 비정수 월(35일 등) — 30일 단위 올림 청구 개월 수
  static int? inferBillingMonthsBetween(DateTime start, DateTime end) {
    final days = end.difference(start).inDays;
    if (days < 30) return null;
    final months = (days + 29) ~/ 30;
    if (months > maxMonthlyMonths) return null;
    return months;
  }

  static DateTime maxReturnDay(DateTime startDay) => addMonths(startDay, maxMonthlyMonths);

  /// start/end + rental_type으로 기본 요금 계산 (서버 calc_rental_base_price 동일)
  static int? calculateBasePriceFromInterval({
    required int pricePerHour,
    int? dailyPrice,
    int? monthlyPrice,
    required RentalType type,
    required DateTime start,
    required DateTime end,
  }) {
    final effectiveDaily =
        dailyPrice ?? pricePerHour * dailyFromHourlyMultiplier;
    final effectiveMonthly =
        monthlyPrice ?? effectiveDaily * monthlyFromDailyMultiplier;

    switch (type) {
      case RentalType.hourly:
        final hours = inferHoursBetween(start, end);
        if (hours == null) return null;
        return hours * pricePerHour;
      case RentalType.daily:
        final days = inferDaysBetween(start, end);
        if (days == null) return null;
        return days * effectiveDaily;
      case RentalType.monthly:
        final months =
            inferMonthsBetween(start, end) ?? inferBillingMonthsBetween(start, end);
        if (months == null) return null;
        return months * effectiveMonthly;
    }
  }

  static int? calculateBasePriceFromIntervalVehicle(
    Vehicle vehicle,
    RentalType type, {
    required DateTime start,
    required DateTime end,
  }) {
    return calculateBasePriceFromInterval(
      pricePerHour: vehicle.pricePerHour,
      dailyPrice: vehicle.dailyPrice,
      monthlyPrice: vehicle.monthlyPrice,
      type: type,
      start: start,
      end: end,
    );
  }
}
