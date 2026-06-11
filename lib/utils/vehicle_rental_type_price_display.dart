import 'package:intl/intl.dart';

import '../models/staff_profile.dart';
import '../models/vehicle.dart';
import 'rental_pricing.dart';

/// 활성 대여 유형별 요금 라벨 (차량 상세·수정 화면 공통)
List<String> buildVehicleRentalTypePriceLines(
  Vehicle vehicle, {
  NumberFormat? won,
}) {
  return buildActiveRentalTypePriceLines(
    rentalTypes: vehicle.rentalTypes,
    pricePerHour: vehicle.pricePerHour,
    dailyPrice: vehicle.dailyPrice,
    monthlyPrice: vehicle.monthlyPrice,
    monthlyExcessDailyPrice: vehicle.monthlyExcessDailyPrice,
    won: won,
  );
}

List<String> buildAdminVehicleRentalTypePriceLines(
  AdminVehicleDetail vehicle, {
  NumberFormat? won,
}) {
  return buildActiveRentalTypePriceLines(
    rentalTypes: vehicle.rentalTypes,
    pricePerHour: vehicle.pricePerHour,
    dailyPrice: vehicle.dailyPrice,
    monthlyPrice: vehicle.monthlyPrice,
    monthlyExcessDailyPrice: vehicle.monthlyExcessDailyPrice,
    won: won,
  );
}

List<String> buildActiveRentalTypePriceLines({
  required List<RentalType> rentalTypes,
  required int pricePerHour,
  int? dailyPrice,
  int? monthlyPrice,
  int? monthlyExcessDailyPrice,
  NumberFormat? won,
}) {
  final formatter = won ?? NumberFormat('#,###');
  final lines = <String>[];
  const order = [RentalType.hourly, RentalType.daily, RentalType.monthly];

  for (final type in order) {
    if (!rentalTypes.contains(type)) continue;
    switch (type) {
      case RentalType.hourly:
        if (pricePerHour > 0) {
          lines.add('시간 ₩${formatter.format(pricePerHour)}/h');
        }
        break;
      case RentalType.daily:
        final daily = dailyPrice;
        if (daily != null && daily > 0) {
          lines.add('일 ₩${formatter.format(daily)}');
        }
        break;
      case RentalType.monthly:
        final monthly = monthlyPrice;
        if (monthly != null && monthly > 0) {
          var line = '월 ₩${formatter.format(monthly)}';
          final excess = monthlyExcessDailyPrice;
          if (excess != null && excess > 0) {
            line += ' · 초과 일요금 ₩${formatter.format(excess)}';
          }
          lines.add(line);
        }
        break;
    }
  }

  return lines;
}
