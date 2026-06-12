import '../models/vehicle.dart';
import 'rental_pricing.dart';

/// 예약 차량 카드 가격 영역 — 일 단가 비교·절약 (표시 전용, 요금 산출과 무관)
class BookingVehiclePriceLines {
  final int? dailyCompareAmount;
  final int appliedAmount;
  final RentalType periodType;
  final int? savings;
  final bool showMonthlyOnlyLabel;
  final bool monthlyCapApplied;
  final int periodDays;

  const BookingVehiclePriceLines({
    this.dailyCompareAmount,
    required this.appliedAmount,
    required this.periodType,
    this.savings,
    this.showMonthlyOnlyLabel = false,
    this.monthlyCapApplied = false,
    this.periodDays = 0,
  });

  bool get showDailyCompare =>
      dailyCompareAmount != null && dailyCompareAmount! > 0;

  bool get showSavings => savings != null && savings! > 0;

  /// 구간 총액 표기용 단위 — 산출 분기와 동일
  String appliedAmountSuffix() {
    if (monthlyCapApplied || periodType == RentalType.monthly) {
      return '/월';
    }
    if (periodType == RentalType.daily && periodDays == 1) {
      return '/일';
    }
    return '';
  }
}

bool isMonthlyOnlyVehicle(Vehicle vehicle) {
  final types = vehicle.rentalTypes;
  return types.contains(RentalType.monthly) && !types.contains(RentalType.daily);
}

BookingVehiclePriceLines? buildBookingVehiclePriceLines(
  Vehicle vehicle,
  RentalType periodType, {
  required DateTime start,
  required DateTime end,
}) {
  final breakdown = RentalPricing.calculateBasePriceBreakdownFromVehicle(
    vehicle,
    periodType,
    start: start,
    end: end,
  );
  if (breakdown == null) return null;

  final applied = breakdown.amount;
  final days = end.difference(start).inDays;
  final monthlyCapApplied = breakdown.monthlyCapApplied;

  final hasDaily = vehicle.rentalTypes.contains(RentalType.daily);
  if (!hasDaily || periodType == RentalType.hourly) {
    return BookingVehiclePriceLines(
      appliedAmount: applied,
      periodType: periodType,
      monthlyCapApplied: monthlyCapApplied,
      periodDays: days,
      showMonthlyOnlyLabel:
          periodType == RentalType.monthly && isMonthlyOnlyVehicle(vehicle),
    );
  }

  if (days < 1) {
    return BookingVehiclePriceLines(
      appliedAmount: applied,
      periodType: periodType,
      monthlyCapApplied: monthlyCapApplied,
      periodDays: days,
    );
  }

  final dailySum = days * RentalPricing.effectiveDailyPrice(vehicle);
  if (dailySum <= applied) {
    return BookingVehiclePriceLines(
      appliedAmount: applied,
      periodType: periodType,
      monthlyCapApplied: monthlyCapApplied,
      periodDays: days,
    );
  }

  return BookingVehiclePriceLines(
    dailyCompareAmount: dailySum,
    appliedAmount: applied,
    periodType: periodType,
    monthlyCapApplied: monthlyCapApplied,
    periodDays: days,
    savings: dailySum - applied,
  );
}
