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
  final int todaySales;
  final int monthSales;

  const BranchStats({
    required this.totalVehicles,
    required this.availableVehicles,
    required this.inOperation,
    required this.todayReservations,
    required this.todaySales,
    required this.monthSales,
  });

  static const empty = BranchStats(
    totalVehicles: 0,
    availableVehicles: 0,
    inOperation: 0,
    todayReservations: 0,
    todaySales: 0,
    monthSales: 0,
  );
}

/// 관리자 — 단지 사업자 정보 (complexes)
class AdminComplexBusinessInfo {
  final String complexId;
  final String? complexName;
  final String? businessName;
  final String? businessRegistrationNumber;
  final String? businessAddress;
  final String? businessRepresentative;
  final String? businessPhone;
  final String? businessLicenseUrl;

  const AdminComplexBusinessInfo({
    required this.complexId,
    this.complexName,
    this.businessName,
    this.businessRegistrationNumber,
    this.businessAddress,
    this.businessRepresentative,
    this.businessPhone,
    this.businessLicenseUrl,
  });

  factory AdminComplexBusinessInfo.fromMap(Map<String, dynamic> map) {
    return AdminComplexBusinessInfo(
      complexId: map['id']?.toString() ?? '',
      complexName: map['name']?.toString(),
      businessName: map['business_name']?.toString(),
      businessRegistrationNumber:
          map['business_registration_number']?.toString(),
      businessAddress: map['business_address']?.toString(),
      businessRepresentative: map['business_representative']?.toString(),
      businessPhone: map['business_phone']?.toString(),
      businessLicenseUrl: map['business_license_url']?.toString(),
    );
  }

  Map<String, dynamic> toUpdateMap() {
    String? emptyToNull(String? v) {
      final t = v?.trim();
      return t == null || t.isEmpty ? null : t;
    }

    return {
      'business_name': emptyToNull(businessName),
      'business_registration_number':
          emptyToNull(businessRegistrationNumber),
      'business_address': emptyToNull(businessAddress),
      'business_representative': emptyToNull(businessRepresentative),
      'business_phone': emptyToNull(businessPhone),
      'business_license_url': emptyToNull(businessLicenseUrl),
    };
  }

  AdminComplexBusinessInfo copyWith({
    String? businessName,
    String? businessRegistrationNumber,
    String? businessAddress,
    String? businessRepresentative,
    String? businessPhone,
    String? businessLicenseUrl,
  }) {
    return AdminComplexBusinessInfo(
      complexId: complexId,
      complexName: complexName,
      businessName: businessName ?? this.businessName,
      businessRegistrationNumber:
          businessRegistrationNumber ?? this.businessRegistrationNumber,
      businessAddress: businessAddress ?? this.businessAddress,
      businessRepresentative:
          businessRepresentative ?? this.businessRepresentative,
      businessPhone: businessPhone ?? this.businessPhone,
      businessLicenseUrl: businessLicenseUrl ?? this.businessLicenseUrl,
    );
  }
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
  final String? ownerName;
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
    this.ownerName,
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
      name: map['model_name']?.toString() ?? '차량',
      vehicleType: map['vehicle_type']?.toString() ??
          map['car_type']?.toString() ??
          '기타',
      fuelType: map['fuel_type']?.toString(),
      pricePerHour: (map['price_per_hour'] as num?)?.toInt() ??
          (map['hourly_rate'] as num?)?.toInt() ??
          0,
      parkingLocation: map['parking_location']?.toString(),
      carNumber: map['car_number']?.toString(),
      ownerName: map['owner_name']?.toString(),
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
      'owner_name': ownerName,
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
      'owner_name': ownerName,
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

  AdminVehicleDetail withComplexName(String name) {
    return AdminVehicleDetail(
      id: id,
      complexId: complexId,
      complexName: name,
      name: this.name,
      vehicleType: vehicleType,
      fuelType: fuelType,
      pricePerHour: pricePerHour,
      parkingLocation: parkingLocation,
      carNumber: carNumber,
      ownerName: ownerName,
      isAvailable: isAvailable,
      insuranceCompany: insuranceCompany,
      insurancePolicyNumber: insurancePolicyNumber,
      insuranceExpiresAt: insuranceExpiresAt,
      lastLatitude: lastLatitude,
      lastLongitude: lastLongitude,
      lastLocationUpdatedAt: lastLocationUpdatedAt,
    );
  }
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
  final List<String> pickupPhotos;
  final List<String> returnPhotos;
  final String? renterName;
  final String? contractContent;
  final String? returnType;
  final DateTime? returnedAt;
  final DateTime? updatedAt;
  final String? secondDriverName;
  final String? secondDriverLicense;
  final bool deductibleCharged;
  final int deductibleAmount;
  final DateTime? deductibleChargedAt;
  final bool deductibleWaived;

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
    this.pickupPhotos = const [],
    this.returnPhotos = const [],
    this.renterName,
    this.contractContent,
    this.returnType,
    this.returnedAt,
    this.updatedAt,
    this.secondDriverName,
    this.secondDriverLicense,
    this.deductibleCharged = false,
    this.deductibleAmount = 0,
    this.deductibleChargedAt,
    this.deductibleWaived = false,
  });

  static const int defaultDeductibleAmount = 500000;

  /// 시간 초과 자동 반납(노쇼) — return_type = 'auto'
  bool get isNoShowReturn =>
      returnType?.trim().toLowerCase() == 'auto';

  bool get hasSecondDriver {
    final name = secondDriverName?.trim();
    return name != null && name.isNotEmpty;
  }

  String get reservationNumberLabel => '#$id';

  /// UI 표시용 — [renterName] 없으면 '이름 미등록'
  String get renterDisplayName {
    final name = renterName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return '이름 미등록';
  }

  /// full_name → 이메일 @ 앞부분 → 이름 미등록 (레거시 '임차인'은 무시)
  static String resolveRenterDisplayName({
    String? directRenterName,
    String? fullName,
    String? name,
    String? email,
  }) {
    final direct = directRenterName?.trim();
    if (direct != null &&
        direct.isNotEmpty &&
        direct != '임차인') {
      return direct;
    }

    final resolvedName = fullName?.trim().isNotEmpty == true
        ? fullName!.trim()
        : (name?.trim().isNotEmpty == true ? name!.trim() : null);
    if (resolvedName != null) return resolvedName;

    final mail = email?.trim();
    if (mail != null && mail.isNotEmpty) {
      final at = mail.indexOf('@');
      if (at > 0) return mail.substring(0, at);
      return mail;
    }

    return '이름 미등록';
  }

  static String _reservationIdFromMap(Map<String, dynamic> map) {
    final raw = map['id'] ?? map['reservation_id'];
    return raw?.toString().trim() ?? '';
  }

  static List<String> _photoUrlsFromMap(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final raw = map[key];
      if (raw is List && raw.isNotEmpty) {
        return raw
            .map((e) => e.toString().trim())
            .where((url) => url.isNotEmpty)
            .toList();
      }
    }
    return const [];
  }

  static String? _renterNameFromMap(Map<String, dynamic> map) {
    final profileRaw = map['user_profiles'];
    Map<String, dynamic>? profile;
    if (profileRaw is Map) {
      profile = Map<String, dynamic>.from(profileRaw);
    }

    return resolveRenterDisplayName(
      directRenterName: map['renter_name']?.toString(),
      fullName: profile?['full_name']?.toString(),
      name: profile?['name']?.toString(),
      email: profile?['email']?.toString(),
    );
  }

  factory AdminReservationRow.fromMap(Map<String, dynamic> map) {
    final vehicleRaw = map['vehicles'];
    final vehicle =
        vehicleRaw is Map ? Map<String, dynamic>.from(vehicleRaw) : null;
    final contract = map['contract_content']?.toString().trim();

    return AdminReservationRow(
      id: _reservationIdFromMap(map),
      status: map['status']?.toString() ?? '',
      totalPrice: (map['total_price'] as num?)?.toInt() ?? 0,
      startAt: DateTime.tryParse(
        (map['start_at'] ?? map['start_time'])?.toString() ?? '',
      )?.toLocal(),
      endAt: DateTime.tryParse(
        (map['end_at'] ?? map['end_time'])?.toString() ?? '',
      )?.toLocal(),
      vehicleName: vehicle?['model_name']?.toString() ?? '차량',
      carNumber: vehicle?['car_number']?.toString(),
      isAccident: map['is_accident'] == true,
      accidentNote: map['accident_note']?.toString(),
      pickupPhotos: _photoUrlsFromMap(
        map,
        ['pickup_photos', 'before_photos'],
      ),
      returnPhotos: _photoUrlsFromMap(
        map,
        ['return_photos', 'after_photos'],
      ),
      renterName: _renterNameFromMap(map),
      contractContent:
          contract != null && contract.isNotEmpty ? contract : null,
      returnType: map['return_type']?.toString(),
      returnedAt: DateTime.tryParse(map['returned_at']?.toString() ?? '')
          ?.toLocal(),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '')
          ?.toLocal(),
      secondDriverName: map['second_driver_name']?.toString(),
      secondDriverLicense: map['second_driver_license']?.toString(),
      deductibleCharged: map['deductible_charged'] == true,
      deductibleAmount: (map['deductible_amount'] as num?)?.toInt() ?? 0,
      deductibleChargedAt: DateTime.tryParse(
        map['deductible_charged_at']?.toString() ?? '',
      )?.toLocal(),
      deductibleWaived: map['deductible_waived'] == true,
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
