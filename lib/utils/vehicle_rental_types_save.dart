import 'package:flutter/material.dart';

import '../models/staff_profile.dart';
import 'rental_pricing.dart';
import 'vehicle_rental_type_price_guard.dart';

/// 대여 유형·요금 저장 전 검증 및 가드 다이얼로그 (수정·상세 화면 공통)
class VehicleRentalTypesSaveData {
  final Set<RentalType> rentalTypes;
  final int pricePerHour;
  final int? dailyPrice;
  final int? monthlyPrice;
  final int? monthlyExcessDailyPrice;

  const VehicleRentalTypesSaveData({
    required this.rentalTypes,
    required this.pricePerHour,
    this.dailyPrice,
    this.monthlyPrice,
    this.monthlyExcessDailyPrice,
  });
}

abstract final class VehicleRentalTypesSaveHelper {
  static String? validateFields({
    required Set<RentalType> rentalTypes,
    required int hourlyPrice,
    required String dailyText,
    required String monthlyText,
    required String excessText,
  }) {
    if (rentalTypes.isEmpty) {
      return '대여 유형을 1개 이상 선택해주세요.';
    }
    if (rentalTypes.contains(RentalType.hourly) && hourlyPrice < 0) {
      return '시간당 요금을 올바르게 입력해주세요.';
    }
    final dailyPrice = dailyText.isEmpty ? null : int.tryParse(dailyText);
    if (dailyPrice != null && dailyPrice < 0) {
      return '1일 요금을 올바르게 입력해주세요.';
    }
    final monthlyPrice = monthlyText.isEmpty ? null : int.tryParse(monthlyText);
    if (monthlyPrice != null && monthlyPrice < 0) {
      return '월 요금을 올바르게 입력해주세요.';
    }
    final excessPrice = excessText.isEmpty ? null : int.tryParse(excessText);
    if (excessPrice != null && excessPrice < 0) {
      return '초과 일요금을 올바르게 입력해주세요.';
    }
    return null;
  }

  static Future<VehicleRentalTypesSaveData?> prepareForSave(
    BuildContext context, {
    required Set<RentalType> rentalTypes,
    required int hourlyPrice,
    required String dailyText,
    required String monthlyText,
    required String excessText,
  }) async {
    final validationError = validateFields(
      rentalTypes: rentalTypes,
      hourlyPrice: hourlyPrice,
      dailyText: dailyText,
      monthlyText: monthlyText,
      excessText: excessText,
    );
    if (validationError != null) {
      return null;
    }

    var types = Set<RentalType>.from(rentalTypes);
    final missingPrices = VehicleRentalTypePriceGuard.findTypesMissingPrice(
      types: types,
      hourlyPrice: hourlyPrice,
      dailyPriceText: dailyText,
      monthlyPriceText: monthlyText,
    );
    if (missingPrices.isNotEmpty) {
      final choice = await VehicleRentalTypePriceGuard.showSaveGuardDialog(
        context,
        missingPrices,
      );
      if (choice != VehicleRentalTypeSaveGuardChoice.saveWithTogglesOff) {
        return null;
      }
      types.removeAll(missingPrices);
      if (types.isEmpty) {
        return null;
      }
    }

    final dailyPrice = dailyText.isEmpty ? null : int.tryParse(dailyText.trim());
    final monthlyPrice =
        monthlyText.isEmpty ? null : int.tryParse(monthlyText.trim());
    final excessPrice =
        excessText.isEmpty ? null : int.tryParse(excessText.trim());

    return VehicleRentalTypesSaveData(
      rentalTypes: types,
      pricePerHour: types.contains(RentalType.hourly) ? hourlyPrice : 0,
      dailyPrice: dailyPrice,
      monthlyPrice: monthlyPrice,
      monthlyExcessDailyPrice: excessPrice,
    );
  }

  static AdminVehicleDetail applyToVehicle(
    AdminVehicleDetail vehicle,
    VehicleRentalTypesSaveData data,
  ) {
    return AdminVehicleDetail(
      id: vehicle.id,
      complexId: vehicle.complexId,
      complexName: vehicle.complexName,
      name: vehicle.name,
      vehicleType: vehicle.vehicleType,
      fuelType: vehicle.fuelType,
      pricePerHour: data.pricePerHour,
      dailyPrice: data.dailyPrice,
      monthlyPrice: data.monthlyPrice,
      monthlyExcessDailyPrice: data.monthlyExcessDailyPrice,
      rentalTypes: data.rentalTypes.toList(),
      parkingLocation: vehicle.parkingLocation,
      carNumber: vehicle.carNumber,
      ownerName: vehicle.ownerName,
      isPublished: vehicle.isPublished,
      isAvailable: vehicle.isAvailable,
      insuranceCompany: vehicle.insuranceCompany,
      insurancePolicyNumber: vehicle.insurancePolicyNumber,
      insuranceExpiresAt: vehicle.insuranceExpiresAt,
      totalMileage: vehicle.totalMileage,
      isUnderMaintenance: vehicle.isUnderMaintenance,
      maintenanceMemo: vehicle.maintenanceMemo,
    );
  }
}
