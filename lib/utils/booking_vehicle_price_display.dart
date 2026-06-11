import '../models/vehicle.dart';
import 'rental_pricing.dart';

/// 예약 차량 카드 가격 영역 — 일 단가 비교·절약 (표시 전용, 요금 산출과 무관)
class BookingVehiclePriceLines {
  final int? dailyCompareAmount;
  final int appliedAmount;
  final RentalType periodType;
  final int? savings;
  final bool showMonthlyOnlyLabel;

  const BookingVehiclePriceLines({
    this.dailyCompareAmount,
    required this.appliedAmount,
    required this.periodType,
    this.savings,
    this.showMonthlyOnlyLabel = false,
  });

  bool get showDailyCompare =>
      dailyCompareAmount != null && dailyCompareAmount! > 0;

  bool get showSavings => savings != null && savings! > 0;
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
  final applied = RentalPricing.calculateBasePriceFromIntervalVehicle(
    vehicle,
    periodType,
    start: start,
    end: end,
  );
  if (applied == null) return null;

  final hasDaily = vehicle.rentalTypes.contains(RentalType.daily);
  if (!hasDaily || periodType == RentalType.hourly) {
    return BookingVehiclePriceLines(
      appliedAmount: applied,
      periodType: periodType,
      showMonthlyOnlyLabel:
          periodType == RentalType.monthly && isMonthlyOnlyVehicle(vehicle),
    );
  }

  final days = end.difference(start).inDays;
  if (days < 1) {
    return BookingVehiclePriceLines(
      appliedAmount: applied,
      periodType: periodType,
    );
  }

  final dailySum = days * RentalPricing.effectiveDailyPrice(vehicle);
  if (dailySum <= applied) {
    return BookingVehiclePriceLines(
      appliedAmount: applied,
      periodType: periodType,
    );
  }

  return BookingVehiclePriceLines(
    dailyCompareAmount: dailySum,
    appliedAmount: applied,
    periodType: periodType,
    savings: dailySum - applied,
  );
}
