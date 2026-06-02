class StaffProfile {
  final String userId;
  final String complexId;
  final String displayName;
  final String role;
  final bool approved;
  final String? complexName;
  final String? phone;
  final String? companyName;

  const StaffProfile({
    required this.userId,
    required this.complexId,
    required this.displayName,
    required this.role,
    required this.approved,
    this.complexName,
    this.phone,
    this.companyName,
  });

  bool get isApproved => approved;

  factory StaffProfile.fromMap(Map<String, dynamic> map) {
    final complexRaw = map['complexes'];
    final complexMap =
        complexRaw is Map ? Map<String, dynamic>.from(complexRaw) : null;

    return StaffProfile(
      userId: map['user_id']?.toString() ?? '',
      complexId: map['complex_id']?.toString() ?? '',
      displayName: map['display_name']?.toString() ?? '관리자',
      role: map['role']?.toString() ?? 'branch_admin',
      approved: map['approved'] == true,
      complexName: complexMap?['name']?.toString(),
      phone: map['phone']?.toString(),
      companyName: map['company_name']?.toString(),
    );
  }
}

class BranchStats {
  final int totalVehicles;
  final int availableVehicles;
  final int inOperation;
  final int todayReservations;
  final int monthSales;

  const BranchStats({
    required this.totalVehicles,
    required this.availableVehicles,
    required this.inOperation,
    required this.todayReservations,
    required this.monthSales,
  });

  static const empty = BranchStats(
    totalVehicles: 0,
    availableVehicles: 0,
    inOperation: 0,
    todayReservations: 0,
    monthSales: 0,
  );
}

class AdminVehicleDetail {
  final String id;
  final String complexId;
  final String? complexName;
  final String name;
  final String vehicleType;
  final String? fuelType;
  final int pricePerHour;
  final String? parkingLocation;
  final String? carNumber;
  final bool isAvailable;
  final String? insuranceCompany;
  final String? insurancePolicyNumber;
  final DateTime? insuranceExpiresAt;
  final double? lastLatitude;
  final double? lastLongitude;
  final DateTime? lastLocationUpdatedAt;

  const AdminVehicleDetail({
    required this.id,
    required this.complexId,
    this.complexName,
    required this.name,
    required this.vehicleType,
    this.fuelType,
    required this.pricePerHour,
    this.parkingLocation,
    this.carNumber,
    required this.isAvailable,
    this.insuranceCompany,
    this.insurancePolicyNumber,
    this.insuranceExpiresAt,
    this.lastLatitude,
    this.lastLongitude,
    this.lastLocationUpdatedAt,
  });

  factory AdminVehicleDetail.fromMap(Map<String, dynamic> map) {
    final complexRaw = map['complexes'];
    final complexMap =
        complexRaw is Map ? Map<String, dynamic>.from(complexRaw) : null;

    return AdminVehicleDetail(
      id: map['id'].toString(),
      complexId: map['complex_id']?.toString() ?? '',
      complexName: complexMap?['name']?.toString(),
      name: map['model_name']?.toString() ??
          map['name']?.toString() ??
          '차량',
      vehicleType: map['vehicle_type']?.toString() ??
          map['car_type']?.toString() ??
          '기타',
      fuelType: map['fuel_type']?.toString(),
      pricePerHour: (map['price_per_hour'] as num?)?.toInt() ??
          (map['hourly_rate'] as num?)?.toInt() ??
          0,
      parkingLocation: map['parking_location']?.toString(),
      carNumber: map['car_number']?.toString(),
      isAvailable: map['is_available'] as bool? ??
          map['is_active'] as bool? ??
          true,
      insuranceCompany: map['insurance_company']?.toString(),
      insurancePolicyNumber: map['insurance_policy_number']?.toString(),
      insuranceExpiresAt: _parseDate(map['insurance_expires_at']),
      lastLatitude: (map['last_latitude'] as num?)?.toDouble(),
      lastLongitude: (map['last_longitude'] as num?)?.toDouble(),
      lastLocationUpdatedAt: _parseDateTime(map['last_location_updated_at']),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'complex_id': complexId,
      'model_name': name,
      'vehicle_type': vehicleType,
      'fuel_type': fuelType,
      'price_per_hour': pricePerHour,
      'hourly_rate': pricePerHour,
      'parking_location': parkingLocation,
      'car_number': carNumber,
      'is_available': isAvailable,
      'is_active': isAvailable,
      'insurance_company': insuranceCompany,
      'insurance_policy_number': insurancePolicyNumber,
      'insurance_expires_at':
          insuranceExpiresAt?.toIso8601String().split('T').first,
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'complex_id': complexId.isNotEmpty ? complexId : null,
      'model_name': name,
      'vehicle_type': vehicleType,
      'fuel_type': fuelType,
      'price_per_hour': pricePerHour,
      'hourly_rate': pricePerHour,
      'parking_location': parkingLocation,
      'car_number': carNumber,
      'is_available': isAvailable,
      'is_active': isAvailable,
      'insurance_company': insuranceCompany,
      'insurance_policy_number': insurancePolicyNumber,
      'insurance_expires_at':
          insuranceExpiresAt?.toIso8601String().split('T').first,
    };
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  bool get isInsuranceExpired {
    if (insuranceExpiresAt == null) return false;
    return insuranceExpiresAt!.isBefore(DateTime.now());
  }

  bool get hasInsurance =>
      (insuranceCompany?.trim().isNotEmpty ?? false) &&
      (insurancePolicyNumber?.trim().isNotEmpty ?? false);
}

class AdminReservationRow {
  final String id;
  final String status;
  final int totalPrice;
  final DateTime? startAt;
  final DateTime? endAt;
  final String vehicleName;
  final String? carNumber;
  final bool isAccident;
  final String? accidentNote;

  const AdminReservationRow({
    required this.id,
    required this.status,
    required this.totalPrice,
    this.startAt,
    this.endAt,
    required this.vehicleName,
    this.carNumber,
    this.isAccident = false,
    this.accidentNote,
  });

  factory AdminReservationRow.fromMap(Map<String, dynamic> map) {
    final vehicleRaw = map['vehicles'];
    final vehicle =
        vehicleRaw is Map ? Map<String, dynamic>.from(vehicleRaw) : null;

    return AdminReservationRow(
      id: map['id'].toString(),
      status: map['status']?.toString() ?? '',
      totalPrice: (map['total_price'] as num?)?.toInt() ?? 0,
      startAt: DateTime.tryParse(
        (map['start_at'] ?? map['start_time'])?.toString() ?? '',
      )?.toLocal(),
      endAt: DateTime.tryParse(
        (map['end_at'] ?? map['end_time'])?.toString() ?? '',
      )?.toLocal(),
      vehicleName: vehicle?['model_name']?.toString() ??
          vehicle?['name']?.toString() ??
          '차량',
      carNumber: vehicle?['car_number']?.toString(),
      isAccident: map['is_accident'] == true,
      accidentNote: map['accident_note']?.toString(),
    );
  }
}

class SalesSummary {
  final int totalAmount;
  final int reservationCount;
  final List<SalesRow> rows;

  const SalesSummary({
    required this.totalAmount,
    required this.reservationCount,
    required this.rows,
  });
}

class SalesRow {
  final String vehicleName;
  final int amount;
  final int count;

  const SalesRow({
    required this.vehicleName,
    required this.amount,
    required this.count,
  });
}
