class SuperAdminDashboard {
  final int complexCount;
  final int vehicleCount;
  final int availableVehicleCount;
  final int inUseVehicleCount;
  final int staffCount;
  final int staffApprovedCount;
  final int residentCount;
  final int residentApprovedCount;
  final int reservationCountToday;
  final int reservationActiveCount;
  final int todayRevenue;
  final int monthRevenue;
  final int totalRevenue;

  const SuperAdminDashboard({
    this.complexCount = 0,
    this.vehicleCount = 0,
    this.availableVehicleCount = 0,
    this.inUseVehicleCount = 0,
    this.staffCount = 0,
    this.staffApprovedCount = 0,
    this.residentCount = 0,
    this.residentApprovedCount = 0,
    this.reservationCountToday = 0,
    this.reservationActiveCount = 0,
    this.todayRevenue = 0,
    this.monthRevenue = 0,
    this.totalRevenue = 0,
  });

  factory SuperAdminDashboard.fromMap(Map<String, dynamic> m) {
    int i(String k) => (m[k] as num?)?.toInt() ?? 0;
    return SuperAdminDashboard(
      complexCount: i('complex_count'),
      vehicleCount: i('vehicle_count'),
      availableVehicleCount: i('available_vehicle_count'),
      inUseVehicleCount: i('in_use_vehicle_count'),
      staffCount: i('staff_count'),
      staffApprovedCount: i('staff_approved_count'),
      residentCount: i('resident_count'),
      residentApprovedCount: i('resident_approved_count'),
      reservationCountToday: i('reservation_count_today'),
      reservationActiveCount: i('reservation_active_count'),
      todayRevenue: i('today_revenue'),
      monthRevenue: i('month_revenue'),
      totalRevenue: i('total_revenue'),
    );
  }
}

class SuperAdminComplex {
  final String id;
  final String name;
  final String? inviteCode;
  final String? adminInviteCode;
  final String? businessName;
  final String? businessPhone;
  final int vehicleCount;
  final int staffCount;
  final int residentCount;
  final int inUseCount;
  final int monthRevenue;
  final DateTime? createdAt;

  const SuperAdminComplex({
    required this.id,
    required this.name,
    this.inviteCode,
    this.adminInviteCode,
    this.businessName,
    this.businessPhone,
    this.vehicleCount = 0,
    this.staffCount = 0,
    this.residentCount = 0,
    this.inUseCount = 0,
    this.monthRevenue = 0,
    this.createdAt,
  });

  factory SuperAdminComplex.fromMap(Map<String, dynamic> m) {
    return SuperAdminComplex(
      id: m['complex_id']?.toString() ?? '',
      name: m['complex_name']?.toString() ?? '',
      inviteCode: m['invite_code']?.toString(),
      adminInviteCode: m['admin_invite_code']?.toString(),
      businessName: m['business_name']?.toString(),
      businessPhone: m['business_phone']?.toString(),
      vehicleCount: (m['vehicle_count'] as num?)?.toInt() ?? 0,
      staffCount: (m['staff_count'] as num?)?.toInt() ?? 0,
      residentCount: (m['resident_count'] as num?)?.toInt() ?? 0,
      inUseCount: (m['in_use_count'] as num?)?.toInt() ?? 0,
      monthRevenue: (m['month_revenue'] as num?)?.toInt() ?? 0,
      createdAt: _dt(m['created_at']),
    );
  }
}

class SuperAdminVehicle {
  final String id;
  final String complexId;
  final String complexName;
  final String modelName;
  final String? carNumber;
  final String? vehicleType;
  final String? fuelType;
  final int pricePerHour;
  final bool isAvailable;
  final bool inUse;
  final String? currentStatus;
  final String? currentRenterName;

  const SuperAdminVehicle({
    required this.id,
    required this.complexId,
    required this.complexName,
    required this.modelName,
    this.carNumber,
    this.vehicleType,
    this.fuelType,
    this.pricePerHour = 0,
    this.isAvailable = true,
    this.inUse = false,
    this.currentStatus,
    this.currentRenterName,
  });

  factory SuperAdminVehicle.fromMap(Map<String, dynamic> m) {
    return SuperAdminVehicle(
      id: m['vehicle_id']?.toString() ?? '',
      complexId: m['complex_id']?.toString() ?? '',
      complexName: m['complex_name']?.toString() ?? '',
      modelName: m['model_name']?.toString() ?? '차량',
      carNumber: m['car_number']?.toString(),
      vehicleType: m['vehicle_type']?.toString(),
      fuelType: m['fuel_type']?.toString(),
      pricePerHour: (m['price_per_hour'] as num?)?.toInt() ?? 0,
      isAvailable: m['is_available'] == true,
      inUse: m['in_use'] == true,
      currentStatus: m['current_reservation_status']?.toString(),
      currentRenterName: m['current_renter_name']?.toString(),
    );
  }
}

class SuperAdminStaff {
  final String userId;
  final String complexId;
  final String complexName;
  final String displayName;
  final String? phone;
  final String? companyName;
  final bool approved;
  final String? email;
  final DateTime? createdAt;

  const SuperAdminStaff({
    required this.userId,
    required this.complexId,
    required this.complexName,
    required this.displayName,
    this.phone,
    this.companyName,
    this.approved = false,
    this.email,
    this.createdAt,
  });

  factory SuperAdminStaff.fromMap(Map<String, dynamic> m) {
    return SuperAdminStaff(
      userId: m['user_id']?.toString() ?? '',
      complexId: m['complex_id']?.toString() ?? '',
      complexName: m['complex_name']?.toString() ?? '',
      displayName: m['display_name']?.toString() ?? '',
      phone: m['phone']?.toString(),
      companyName: m['company_name']?.toString(),
      approved: m['approved'] == true,
      email: m['email']?.toString(),
      createdAt: _dt(m['created_at']),
    );
  }
}

class SuperAdminResident {
  final String userId;
  final String complexId;
  final String complexName;
  final String? building;
  final String? unit;
  final bool approved;
  final String? fullName;
  final String? phone;
  final String? email;
  final bool licenseVerified;
  final bool isBlacklisted;
  final DateTime? createdAt;

  const SuperAdminResident({
    required this.userId,
    required this.complexId,
    required this.complexName,
    this.building,
    this.unit,
    this.approved = false,
    this.fullName,
    this.phone,
    this.email,
    this.licenseVerified = false,
    this.isBlacklisted = false,
    this.createdAt,
  });

  factory SuperAdminResident.fromMap(Map<String, dynamic> m) {
    return SuperAdminResident(
      userId: m['user_id']?.toString() ?? '',
      complexId: m['complex_id']?.toString() ?? '',
      complexName: m['complex_name']?.toString() ?? '',
      building: m['building']?.toString(),
      unit: m['unit']?.toString(),
      approved: m['approved'] == true,
      fullName: m['full_name']?.toString(),
      phone: m['phone']?.toString(),
      email: m['email']?.toString(),
      licenseVerified: m['license_verified'] == true,
      isBlacklisted: m['is_blacklisted'] == true,
      createdAt: _dt(m['created_at']),
    );
  }
}

class SuperAdminReservation {
  final String id;
  final String complexId;
  final String complexName;
  final String vehicleId;
  final String vehicleName;
  final String? carNumber;
  final String renterName;
  final String renterPhone;
  final String status;
  final DateTime? startAt;
  final DateTime? endAt;
  final int totalPrice;
  final DateTime? createdAt;

  const SuperAdminReservation({
    required this.id,
    required this.complexId,
    required this.complexName,
    required this.vehicleId,
    required this.vehicleName,
    this.carNumber,
    required this.renterName,
    required this.renterPhone,
    required this.status,
    this.startAt,
    this.endAt,
    this.totalPrice = 0,
    this.createdAt,
  });

  factory SuperAdminReservation.fromMap(Map<String, dynamic> m) {
    return SuperAdminReservation(
      id: m['reservation_id']?.toString() ?? '',
      complexId: m['complex_id']?.toString() ?? '',
      complexName: m['complex_name']?.toString() ?? '',
      vehicleId: m['vehicle_id']?.toString() ?? '',
      vehicleName: m['vehicle_name']?.toString() ?? '차량',
      carNumber: m['car_number']?.toString(),
      renterName: m['renter_name']?.toString() ?? '',
      renterPhone: m['renter_phone']?.toString() ?? '',
      status: m['status']?.toString() ?? '',
      startAt: _dt(m['start_at']),
      endAt: _dt(m['end_at']),
      totalPrice: (m['total_price'] as num?)?.toInt() ?? 0,
      createdAt: _dt(m['created_at']),
    );
  }
}

class SuperAdminRevenueRow {
  final String complexId;
  final String complexName;
  final int year;
  final int month;
  final int reservationCount;
  final int grossRevenue;
  final int paidOrderCount;
  final int paidOrderAmount;
  final int extensionRevenue;
  final bool isSettled;
  final DateTime? settledAt;

  const SuperAdminRevenueRow({
    required this.complexId,
    required this.complexName,
    required this.year,
    required this.month,
    this.reservationCount = 0,
    this.grossRevenue = 0,
    this.paidOrderCount = 0,
    this.paidOrderAmount = 0,
    this.extensionRevenue = 0,
    this.isSettled = false,
    this.settledAt,
  });

  int get totalRevenue => grossRevenue + extensionRevenue;

  factory SuperAdminRevenueRow.fromMap(Map<String, dynamic> m) {
    return SuperAdminRevenueRow(
      complexId: m['complex_id']?.toString() ?? '',
      complexName: m['complex_name']?.toString() ?? '',
      year: (m['period_year'] as num?)?.toInt() ?? 0,
      month: (m['period_month'] as num?)?.toInt() ?? 0,
      reservationCount: (m['reservation_count'] as num?)?.toInt() ?? 0,
      grossRevenue: (m['gross_revenue'] as num?)?.toInt() ?? 0,
      paidOrderCount: (m['paid_order_count'] as num?)?.toInt() ?? 0,
      paidOrderAmount: (m['paid_order_amount'] as num?)?.toInt() ?? 0,
      extensionRevenue: (m['extension_revenue'] as num?)?.toInt() ?? 0,
      isSettled: m['is_settled'] == true,
      settledAt: _dt(m['settled_at']),
    );
  }
}

class SuperAdminCoupon {
  final String id;
  final String title;
  final String? description;
  final int discountAmount;
  final int minPaymentAmount;
  final int issuedCount;
  final int usedCount;
  final DateTime? createdAt;

  const SuperAdminCoupon({
    required this.id,
    required this.title,
    this.description,
    this.discountAmount = 0,
    this.minPaymentAmount = 0,
    this.issuedCount = 0,
    this.usedCount = 0,
    this.createdAt,
  });

  factory SuperAdminCoupon.fromMap(Map<String, dynamic> m) {
    return SuperAdminCoupon(
      id: m['coupon_id']?.toString() ?? '',
      title: m['title']?.toString() ?? '쿠폰',
      description: m['description']?.toString(),
      discountAmount: (m['discount_amount'] as num?)?.toInt() ?? 0,
      minPaymentAmount: (m['min_payment_amount'] as num?)?.toInt() ?? 0,
      issuedCount: (m['issued_count'] as num?)?.toInt() ?? 0,
      usedCount: (m['used_count'] as num?)?.toInt() ?? 0,
      createdAt: _dt(m['created_at']),
    );
  }
}

class SuperAdminNotice {
  final String id;
  final String? complexId;
  final String? complexName;
  final String title;
  final String content;
  final bool isActive;
  final bool isGlobal;
  final DateTime? createdAt;

  const SuperAdminNotice({
    required this.id,
    this.complexId,
    this.complexName,
    required this.title,
    required this.content,
    this.isActive = true,
    this.isGlobal = false,
    this.createdAt,
  });

  factory SuperAdminNotice.fromMap(Map<String, dynamic> m) {
    return SuperAdminNotice(
      id: m['notice_id']?.toString() ?? '',
      complexId: m['complex_id']?.toString(),
      complexName: m['complex_name']?.toString(),
      title: m['title']?.toString() ?? '',
      content: m['content']?.toString() ?? '',
      isActive: m['is_active'] == true,
      isGlobal: m['is_global'] == true,
      createdAt: _dt(m['created_at']),
    );
  }
}

class SuperAdminBanner {
  final int id;
  final String subTitle;
  final String mainTitle;
  final String description;
  final bool isActive;

  const SuperAdminBanner({
    required this.id,
    required this.subTitle,
    required this.mainTitle,
    required this.description,
    this.isActive = true,
  });

  factory SuperAdminBanner.fromMap(Map<String, dynamic> m) {
    return SuperAdminBanner(
      id: (m['banner_id'] as num?)?.toInt() ?? 0,
      subTitle: m['sub_title']?.toString() ?? '',
      mainTitle: m['main_title']?.toString() ?? '',
      description: m['description']?.toString() ?? '',
      isActive: m['is_active'] == true,
    );
  }
}

DateTime? _dt(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v.toLocal();
  return DateTime.tryParse(v.toString())?.toLocal();
}
