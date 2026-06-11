import 'rental_pricing.dart';

/// 구간 요금 산출 결과 (서버 calc_rental_base_price 와 동일 규칙)
class RentalPriceBreakdown {
  final int amount;
  final bool monthlyCapApplied;

  const RentalPriceBreakdown({
    required this.amount,
    this.monthlyCapApplied = false,
  });
}

/// 월만 운영 + 초과 일요금: 30일 블록은 월요금, 잔여일은 초과 일요금(월요금 캡)
int monthlyOnlyExcessBilling({
  required int totalDays,
  required int monthly,
  required int excessDaily,
}) {
  final blocks = totalDays ~/ 30;
  final rem = totalDays % 30;
  var total = blocks * monthly;
  if (rem > 0) {
    final remCharge = rem * excessDaily;
    total += remCharge > monthly ? monthly : remCharge;
  }
  return total;
}

/// 일+월 운영: 30일 구간별 min(일요금×일수, 월요금) 합산
({int amount, bool monthlyCapApplied}) dailyMonthlyIntervalBilling({
  required int totalDays,
  required int daily,
  required int monthly,
  required int remainderDailyRate,
}) {
  final blocks = totalDays ~/ 30;
  final rem = totalDays % 30;
  var total = 0;
  var capApplied = false;
  for (var i = 0; i < blocks; i++) {
    final blockRaw = 30 * daily;
    if (blockRaw > monthly) {
      total += monthly;
      capApplied = true;
    } else {
      total += blockRaw;
    }
  }
  if (rem > 0) {
    final remCharge = rem * remainderDailyRate;
    if (remCharge > monthly) {
      total += monthly;
      capApplied = true;
    } else {
      total += remCharge;
    }
  }
  return (amount: total, monthlyCapApplied: capApplied);
}

RentalPriceBreakdown? calculateRentalPriceBreakdown({
  required int pricePerHour,
  int? dailyPrice,
  int? monthlyPrice,
  int? monthlyExcessDailyPrice,
  required List<RentalType> rentalTypes,
  required RentalType type,
  required DateTime start,
  required DateTime end,
}) {
  if (!end.isAfter(start)) return null;

  final types = rentalTypes.isEmpty ? const [RentalType.hourly] : rentalTypes;
  final hasHourly = types.contains(RentalType.hourly);
  final hasDaily = types.contains(RentalType.daily);
  final hasMonthly = types.contains(RentalType.monthly);

  if (!types.contains(type)) return null;

  final effectiveDaily =
      dailyPrice ?? pricePerHour * RentalPricing.dailyFromHourlyMultiplier;
  final effectiveMonthly = monthlyPrice ??
      effectiveDaily * RentalPricing.monthlyFromDailyMultiplier;
  final excessDaily = monthlyExcessDailyPrice;

  if (type == RentalType.hourly) {
    if (!hasHourly) return null;
    final hours = RentalPricing.inferHoursBetween(start, end);
    if (hours == null) return null;
    return RentalPriceBreakdown(amount: hours * pricePerHour);
  }

  final days = end.difference(start).inDays;
  if (days < 1) return null;

  if (type == RentalType.daily) {
    if (!hasDaily) return null;
    if (days > RentalPricing.maxDailyDays) return null;
    if (hasMonthly) {
      final raw = days * effectiveDaily;
      final capped = raw > effectiveMonthly ? effectiveMonthly : raw;
      return RentalPriceBreakdown(
        amount: capped,
        monthlyCapApplied: raw > effectiveMonthly,
      );
    }
    return RentalPriceBreakdown(amount: days * effectiveDaily);
  }

  // monthly (30일+)
  if (!hasMonthly) return null;
  if (days < 30) return null;
  if (days > RentalPricing.maxMonthlyMonths * 30) return null;

  if (hasDaily) {
    final remainderRate = excessDaily ?? effectiveDaily;
    final billed = dailyMonthlyIntervalBilling(
      totalDays: days,
      daily: effectiveDaily,
      monthly: effectiveMonthly,
      remainderDailyRate: remainderRate,
    );
    return RentalPriceBreakdown(
      amount: billed.amount,
      monthlyCapApplied: billed.monthlyCapApplied,
    );
  }

  // 월만 운영
  if (excessDaily == null || excessDaily <= 0) {
    if (days % 30 != 0) return null;
    return RentalPriceBreakdown(amount: (days ~/ 30) * effectiveMonthly);
  }

  final amount = monthlyOnlyExcessBilling(
    totalDays: days,
    monthly: effectiveMonthly,
    excessDaily: excessDaily,
  );
  final uncappedRemainder = (days % 30) * excessDaily;
  return RentalPriceBreakdown(
    amount: amount,
    monthlyCapApplied: days % 30 > 0 && uncappedRemainder > effectiveMonthly,
  );
}

bool vehicleSupportsBookingPeriod({
  required List<RentalType> rentalTypes,
  int? monthlyExcessDailyPrice,
  required RentalType type,
  required DateTime start,
  required DateTime end,
}) {
  if (!rentalTypes.contains(type)) return false;
  if (type == RentalType.daily) {
    return rentalTypes.contains(RentalType.daily);
  }
  if (type == RentalType.monthly) {
    if (!rentalTypes.contains(RentalType.monthly)) return false;
    final days = end.difference(start).inDays;
    if (days < 30) return false;
    final hasDaily = rentalTypes.contains(RentalType.daily);
    final hasExcess =
        monthlyExcessDailyPrice != null && monthlyExcessDailyPrice > 0;
    if (!hasDaily && !hasExcess && days % 30 != 0) return false;
    return true;
  }
  return true;
}

bool fleetAllowsPartialMonthlyReturn({
  required List<({List<RentalType> rentalTypes, int? monthlyExcessDailyPrice})>
      vehicles,
}) {
  return vehicles.any((v) {
    if (!v.rentalTypes.contains(RentalType.monthly)) return false;
    if (v.rentalTypes.contains(RentalType.daily)) return true;
    return v.monthlyExcessDailyPrice != null && v.monthlyExcessDailyPrice! > 0;
  });
}
