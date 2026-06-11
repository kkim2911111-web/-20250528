import '../models/vehicle.dart';
import 'rental_interval_billing.dart' as interval_billing;

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

  /// DB 기본값 hourly만 있을 때 요금 컬럼으로 표시 유형 추론 (UI 전용)
  static List<RentalType> cardDisplayRentalTypes({
    required List<RentalType> rentalTypes,
    required int pricePerHour,
    int? dailyPrice,
    int? monthlyPrice,
  }) {
    final types = rentalTypes.isEmpty ? const [RentalType.hourly] : rentalTypes;
    final hourlyOnly =
        types.length == 1 && types.first == RentalType.hourly;
    if (hourlyOnly && pricePerHour == 0) {
      if (monthlyPrice != null && monthlyPrice > 0) {
        return const [RentalType.monthly];
      }
      if (dailyPrice != null && dailyPrice > 0) {
        return const [RentalType.daily];
      }
    }
    return types;
  }

  /// 관리·목록 카드용 대표 단가 (입주민 카드와 동일, ₩0/h 방지)
  static String cardUnitPriceLabel({
    required int pricePerHour,
    int? dailyPrice,
    int? monthlyPrice,
    required List<RentalType> rentalTypes,
  }) {
    final displayTypes = cardDisplayRentalTypes(
      rentalTypes: rentalTypes,
      pricePerHour: pricePerHour,
      dailyPrice: dailyPrice,
      monthlyPrice: monthlyPrice,
    );
    final vehicle = Vehicle(
      id: '',
      complexId: '',
      name: '',
      vehicleType: '기타',
      pricePerHour: pricePerHour,
      dailyPrice: dailyPrice,
      monthlyPrice: monthlyPrice,
      monthlyExcessDailyPrice: null,
      rentalTypes: displayTypes,
      isAvailable: true,
    );
    return displayUnitPriceLabel(
      vehicle,
      representativeRentalType(vehicle),
    );
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
    DateTime? start,
    DateTime? end,
  }) {
    switch (type) {
      case RentalType.hourly:
        return null;
      case RentalType.daily:
        if (start != null && end != null) {
          final d = end.difference(start).inDays;
          final raw = d * effectiveDailyPrice(vehicle);
          if (vehicle.rentalTypes.contains(RentalType.monthly) &&
              raw > effectiveMonthlyPrice(vehicle)) {
            return raw > 0 ? raw : null;
          }
          final compareHours = d * hoursPerDayForComparison;
          final compare = compareHours * vehicle.pricePerHour;
          return compare > 0 ? compare : null;
        }
        final compareHours = days * hoursPerDayForComparison;
        final compare = compareHours * vehicle.pricePerHour;
        return compare > 0 ? compare : null;
      case RentalType.monthly:
        if (start != null && end != null) {
          final d = end.difference(start).inDays;
          final raw = d * effectiveDailyPrice(vehicle);
          return raw > 0 ? raw : null;
        }
        final compareDays = months * 30;
        final compare = compareDays * effectiveDailyPrice(vehicle);
        return compare > 0 ? compare : null;
    }
  }

  static bool monthlyCapAppliedForInterval(
    Vehicle vehicle,
    RentalType type, {
    required DateTime start,
    required DateTime end,
  }) {
    return calculateBasePriceBreakdownFromVehicle(vehicle, type, start: start, end: end)
            ?.monthlyCapApplied ??
        false;
  }

  static bool vehicleSupportsBookingPeriod(
    Vehicle vehicle,
    RentalType type, {
    required DateTime start,
    required DateTime end,
  }) {
    return interval_billing.vehicleSupportsBookingPeriod(
      rentalTypes: vehicle.rentalTypes,
      monthlyExcessDailyPrice: vehicle.monthlyExcessDailyPrice,
      type: type,
      start: start,
      end: end,
    );
  }

  static bool fleetAllowsPartialMonthlyReturn(Iterable<Vehicle> vehicles) {
    return interval_billing.fleetAllowsPartialMonthlyReturn(
      vehicles: vehicles
          .map(
            (v) => (
              rentalTypes: v.rentalTypes,
              monthlyExcessDailyPrice: v.monthlyExcessDailyPrice,
            ),
          )
          .toList(),
    );
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

  /// 30일 배수 → N개월, 그 외 → N개월 M일 (35일 → 1개월 5일)
  static String formatDurationLabelFromDays(int totalDays) {
    if (totalDays < 1) return '';
    if (totalDays < 30) return '${totalDays}일';
    final blocks = totalDays ~/ 30;
    final rem = totalDays % 30;
    if (rem == 0) {
      return blocks == 1 ? '1개월' : '${blocks}개월';
    }
    final monthPart = blocks == 1 ? '1개월' : '${blocks}개월';
    return '$monthPart $rem일';
  }

  static String formatDurationLabelFromInterval({
    required DateTime start,
    required DateTime end,
  }) {
    if (!end.isAfter(start)) return '';
    final type = inferRentalTypeFromInterval(start: start, end: end);
    switch (type) {
      case RentalType.hourly:
        final hours = inferHoursBetween(start, end);
        return hours != null ? '${hours}시간' : '';
      case RentalType.daily:
        return '${end.difference(start).inDays}일';
      case RentalType.monthly:
        return formatDurationLabelFromDays(end.difference(start).inDays);
    }
  }

  static String rentalTypeUnitSuffix(RentalType type) {
    switch (type) {
      case RentalType.hourly:
        return '/시간';
      case RentalType.daily:
        return '/일';
      case RentalType.monthly:
        return '/월';
    }
  }

  static String durationSummary(
    RentalType type, {
    required int hours,
    required int days,
    required int months,
    DateTime? start,
    DateTime? end,
  }) {
    if (start != null && end != null && end.isAfter(start)) {
      return formatDurationLabelFromInterval(start: start, end: end);
    }
    switch (type) {
      case RentalType.hourly:
        return '${hours}시간';
      case RentalType.daily:
        return '${days}일';
      case RentalType.monthly:
        if (days >= 30) return formatDurationLabelFromDays(days);
        return months == 1 ? '1개월' : '${months}개월';
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

  static interval_billing.RentalPriceBreakdown? calculateBasePriceBreakdownFromInterval({
    required int pricePerHour,
    int? dailyPrice,
    int? monthlyPrice,
    int? monthlyExcessDailyPrice,
    required List<RentalType> rentalTypes,
    required RentalType type,
    required DateTime start,
    required DateTime end,
  }) {
    return interval_billing.calculateRentalPriceBreakdown(
      pricePerHour: pricePerHour,
      dailyPrice: dailyPrice,
      monthlyPrice: monthlyPrice,
      monthlyExcessDailyPrice: monthlyExcessDailyPrice,
      rentalTypes: rentalTypes,
      type: type,
      start: start,
      end: end,
    );
  }

  /// start/end + rental_type으로 기본 요금 (서버 calc_rental_base_price 동일)
  static int? calculateBasePriceFromInterval({
    required int pricePerHour,
    int? dailyPrice,
    int? monthlyPrice,
    int? monthlyExcessDailyPrice,
    required List<RentalType> rentalTypes,
    required RentalType type,
    required DateTime start,
    required DateTime end,
  }) {
    return calculateBasePriceBreakdownFromInterval(
      pricePerHour: pricePerHour,
      dailyPrice: dailyPrice,
      monthlyPrice: monthlyPrice,
      monthlyExcessDailyPrice: monthlyExcessDailyPrice,
      rentalTypes: rentalTypes,
      type: type,
      start: start,
      end: end,
    )?.amount;
  }

  static interval_billing.RentalPriceBreakdown? calculateBasePriceBreakdownFromVehicle(
    Vehicle vehicle,
    RentalType type, {
    required DateTime start,
    required DateTime end,
  }) {
    return calculateBasePriceBreakdownFromInterval(
      pricePerHour: vehicle.pricePerHour,
      dailyPrice: vehicle.dailyPrice,
      monthlyPrice: vehicle.monthlyPrice,
      monthlyExcessDailyPrice: vehicle.monthlyExcessDailyPrice,
      rentalTypes: vehicle.rentalTypes,
      type: type,
      start: start,
      end: end,
    );
  }

  static int? calculateBasePriceFromIntervalVehicle(
    Vehicle vehicle,
    RentalType type, {
    required DateTime start,
    required DateTime end,
  }) {
    return calculateBasePriceBreakdownFromVehicle(vehicle, type, start: start, end: end)
        ?.amount;
  }

  static int? calculatePriceFromInterval(
    Vehicle vehicle,
    RentalType type, {
    required DateTime start,
    required DateTime end,
  }) {
    return calculateBasePriceFromIntervalVehicle(vehicle, type, start: start, end: end);
  }
}
