import '../utils/rental_pricing.dart';
import '../utils/reservation_display.dart';

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
  final int? dailyPrice;
  final int? monthlyPrice;
  final List<RentalType> rentalTypes;
  final String serviceType;
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
    this.dailyPrice,
    this.monthlyPrice,
    this.rentalTypes = const [RentalType.hourly],
    this.serviceType = VehicleServiceType.sharing,
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
      vehicleType: m['car_type']?.toString() ?? 'SUV',
      serviceType: RentalPricing.parseServiceType(
        m['vehicle_type'],
        rentalTypes: RentalPricing.parseRentalTypes(m['rental_types']),
      ),
      fuelType: m['fuel_type']?.toString(),
      pricePerHour: (m['price_per_hour'] as num?)?.toInt() ?? 0,
      dailyPrice: (m['daily_price'] as num?)?.toInt(),
      monthlyPrice: (m['monthly_price'] as num?)?.toInt(),
      rentalTypes: RentalPricing.parseRentalTypes(m['rental_types']),
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
  final String? businessName;
  final String? businessRegistrationNumber;
  final String? businessAddress;
  final String? businessRepresentative;

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
    this.businessName,
    this.businessRegistrationNumber,
    this.businessAddress,
    this.businessRepresentative,
  });

  String? get listCompanyLabel {
    for (final value in [businessName, companyName]) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  bool get hasBusinessInfo {
    for (final value in [
      businessName,
      businessRegistrationNumber,
      businessAddress,
      businessRepresentative,
    ]) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return true;
    }
    return false;
  }

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
      businessName: m['business_name']?.toString(),
      businessRegistrationNumber:
          m['business_registration_number']?.toString(),
      businessAddress: m['business_address']?.toString(),
      businessRepresentative: m['business_representative']?.toString(),
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
  final DateTime? lastRentalAt;

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
    this.lastRentalAt,
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
      lastRentalAt: _dt(m['last_rental_at']),
    );
  }
}

class SuperAdminResidentRental {
  final String reservationId;
  final String? reservationNumber;
  final String vehicleName;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime? rentalStartedAt;
  final DateTime? returnedAt;
  final DateTime? actualEndAt;
  final int totalPrice;
  final String status;
  final String? secondDriverName;
  final String? secondDriverLicense;

  String get reservationNumberLabel => resolveReservationNumberLabel(
        reservationNumber: reservationNumber,
        rawId: reservationId,
      );

  const SuperAdminResidentRental({
    required this.reservationId,
    this.reservationNumber,
    required this.vehicleName,
    this.startAt,
    this.endAt,
    this.rentalStartedAt,
    this.returnedAt,
    this.actualEndAt,
    this.totalPrice = 0,
    required this.status,
    this.secondDriverName,
    this.secondDriverLicense,
  });

  DateTime? get displayRentalStartAt => rentalStartedAt ?? startAt;

  DateTime? get displayRentalEndAt =>
      returnedAt ?? actualEndAt ?? endAt;

  factory SuperAdminResidentRental.fromMap(Map<String, dynamic> m) {
    return SuperAdminResidentRental(
      reservationId: m['reservation_id']?.toString() ?? '',
      reservationNumber: m['reservation_number']?.toString(),
      vehicleName: m['vehicle_name']?.toString() ?? '차량',
      startAt: _dt(m['start_at']),
      endAt: _dt(m['end_at']),
      rentalStartedAt: _dt(m['rental_started_at']),
      returnedAt: _dt(m['returned_at']),
      actualEndAt: _dt(m['actual_end_at']),
      totalPrice: (m['total_price'] as num?)?.toInt() ?? 0,
      status: m['status']?.toString() ?? '',
      secondDriverName: m['second_driver_name']?.toString(),
      secondDriverLicense: m['second_driver_license']?.toString(),
    );
  }
}

class SuperAdminResidentDetail {
  final String userId;
  final String complexId;
  final String complexName;
  final String? building;
  final String? unit;
  final bool approved;
  final String? fullName;
  final String? phone;
  final String? email;
  final bool isBlacklisted;
  final bool licenseVerified;
  final String licenseStatus;
  final String? licenseNumber;
  final String? licenseExpiry;
  final int points;
  final int couponCount;
  final int rentalCount;
  final DateTime? createdAt;
  final DateTime? lastRentalAt;
  final List<SuperAdminResidentRental> rentals;

  const SuperAdminResidentDetail({
    required this.userId,
    required this.complexId,
    required this.complexName,
    this.building,
    this.unit,
    this.approved = false,
    this.fullName,
    this.phone,
    this.email,
    this.isBlacklisted = false,
    this.licenseVerified = false,
    this.licenseStatus = 'none',
    this.licenseNumber,
    this.licenseExpiry,
    this.points = 0,
    this.couponCount = 0,
    this.rentalCount = 0,
    this.createdAt,
    this.lastRentalAt,
    this.rentals = const [],
  });

  factory SuperAdminResidentDetail.fromMap(Map<String, dynamic> m) {
    final rentalsRaw = m['rentals'];
    final rentals = rentalsRaw is List
        ? rentalsRaw
            .map(
              (e) => SuperAdminResidentRental.fromMap(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList()
        : <SuperAdminResidentRental>[];

    return SuperAdminResidentDetail(
      userId: m['user_id']?.toString() ?? '',
      complexId: m['complex_id']?.toString() ?? '',
      complexName: m['complex_name']?.toString() ?? '',
      building: m['building']?.toString(),
      unit: m['unit']?.toString(),
      approved: m['approved'] == true,
      fullName: m['full_name']?.toString(),
      phone: m['phone']?.toString(),
      email: m['email']?.toString(),
      isBlacklisted: m['is_blacklisted'] == true,
      licenseVerified: m['license_verified'] == true,
      licenseStatus: m['license_status']?.toString() ?? 'none',
      licenseNumber: m['license_number']?.toString(),
      licenseExpiry: m['license_expiry']?.toString(),
      points: (m['points'] as num?)?.toInt() ?? 0,
      couponCount: (m['coupon_count'] as num?)?.toInt() ?? 0,
      rentalCount: (m['rental_count'] as num?)?.toInt() ?? 0,
      createdAt: _dt(m['created_at']),
      lastRentalAt: _dt(m['last_rental_at']),
      rentals: rentals,
    );
  }
}

/// 임차인 이용·노쇼 집계 (바텀시트 전용)
class SuperAdminRenterUsageStats {
  final int usageCount;
  final int noShowCount;

  const SuperAdminRenterUsageStats({
    this.usageCount = 0,
    this.noShowCount = 0,
  });

  static const empty = SuperAdminRenterUsageStats();

  String formatLine(String renterName) {
    final usage = '이용 $usageCount건';
    if (noShowCount <= 0) {
      return '$renterName · $usage';
    }
    return '$renterName · $usage · 노쇼 $noShowCount건';
  }
}

class SuperAdminReservation {
  final String id;
  final String? reservationNumber;
  final String complexId;
  final String complexName;
  final String vehicleId;
  final String vehicleName;
  final String? carNumber;
  final String renterName;
  final String renterPhone;
  final String status;
  final bool isNoShow;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime? rentalStartedAt;
  final DateTime? returnedAt;
  final DateTime? actualEndAt;
  final int totalPrice;
  final DateTime? createdAt;
  final List<String> pickupPhotos;
  final List<String> returnPhotos;
  final RentalType? rentalType;

  const SuperAdminReservation({
    required this.id,
    this.reservationNumber,
    required this.complexId,
    required this.complexName,
    required this.vehicleId,
    required this.vehicleName,
    this.carNumber,
    required this.renterName,
    required this.renterPhone,
    required this.status,
    this.isNoShow = false,
    this.startAt,
    this.endAt,
    this.rentalStartedAt,
    this.returnedAt,
    this.actualEndAt,
    this.totalPrice = 0,
    this.createdAt,
    this.pickupPhotos = const [],
    this.returnPhotos = const [],
    this.rentalType,
  });

  DateTime? get displayRentalStartAt => rentalStartedAt ?? startAt;

  DateTime? get displayRentalEndAt =>
      returnedAt ?? actualEndAt ?? endAt;

  /// 실제 반납 시각 (returned_at 우선, 없으면 actual_end_at)
  DateTime? get actualReturnAt => returnedAt ?? actualEndAt;

  bool get canShowForceReturnButton {
    if (isNoShow) return false;
    return status.trim().toLowerCase() == 'in_use';
  }

  bool get canShowPaymentCancelButton {
    if (isNoShow) return false;
    final s = status.trim().toLowerCase();
    return s == 'confirmed' || s == 'in_use';
  }

  bool get showForceActionButtons =>
      canShowForceReturnButton || canShowPaymentCancelButton;

  String get reservationNumberLabel {
    final number = reservationNumber?.trim();
    if (number != null && number.isNotEmpty) return number;
    final raw = this.id.trim();
    return raw.isEmpty ? '—' : '#$raw';
  }

  factory SuperAdminReservation.fromMap(Map<String, dynamic> m) {
    return SuperAdminReservation(
      id: m['reservation_id']?.toString() ?? '',
      reservationNumber: m['reservation_number']?.toString(),
      complexId: m['complex_id']?.toString() ?? '',
      complexName: m['complex_name']?.toString() ?? '',
      vehicleId: m['vehicle_id']?.toString() ?? '',
      vehicleName: m['vehicle_name']?.toString() ?? '차량',
      carNumber: m['car_number']?.toString(),
      renterName: m['renter_name']?.toString() ?? '',
      renterPhone: m['renter_phone']?.toString() ?? '',
      status: m['status']?.toString() ?? '',
      isNoShow: m['is_no_show'] == true,
      startAt: _dt(m['start_at']),
      endAt: _dt(m['end_at']),
      rentalStartedAt: _dt(m['rental_started_at']),
      returnedAt: _dt(m['returned_at']),
      actualEndAt: _dt(m['actual_end_at']),
      totalPrice: (m['total_price'] as num?)?.toInt() ?? 0,
      createdAt: _dt(m['created_at']),
      pickupPhotos: _stringList(m['pickup_photos']),
      returnPhotos: _stringList(m['return_photos']),
      rentalType: RentalType.fromDb(m['rental_type']?.toString()),
    );
  }
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return raw.map((e) => e.toString()).toList();
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
  final bool isRequested;
  final DateTime? settledAt;
  final DateTime? requestedAt;
  final int billableVehicleCount;
  final bool isFeeEstimate;

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
    this.isRequested = false,
    this.settledAt,
    this.requestedAt,
    this.billableVehicleCount = 0,
    this.isFeeEstimate = false,
  });

  int get totalRevenue => grossRevenue + extensionRevenue;

  int get platformFeeAmount => billableVehicleCount * 100000;

  String get settlementBadgeLabel {
    if (isSettled) return '완료';
    if (isRequested) return '정산요청';
    return '미정산';
  }

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
      isRequested: m['is_requested'] == true,
      settledAt: _dt(m['settled_at']),
      requestedAt: _dt(m['requested_at']),
      billableVehicleCount: (m['billable_vehicle_count'] as num?)?.toInt() ?? 0,
      isFeeEstimate: m['is_fee_estimate'] == true,
    );
  }
}

class SuperAdminSettlementSheet {
  final int totalPaid;
  final int cancelRefund;
  final int netRevenue;
  final int paymentCount;
  final int cancelCount;
  final int rentalCount;
  final bool isSettled;
  final bool isRequested;
  final List<SuperAdminSettlementReservation> items;
  final List<SuperAdminSettlementPaymentItem> paymentItems;
  final List<SuperAdminSettlementCancelItem> cancelItems;

  const SuperAdminSettlementSheet({
    this.totalPaid = 0,
    this.cancelRefund = 0,
    this.netRevenue = 0,
    this.paymentCount = 0,
    this.cancelCount = 0,
    this.rentalCount = 0,
    this.isSettled = false,
    this.isRequested = false,
    this.items = const [],
    this.paymentItems = const [],
    this.cancelItems = const [],
  });

  factory SuperAdminSettlementSheet.fromRpc(dynamic data) {
    if (data is! Map) {
      return const SuperAdminSettlementSheet();
    }
    final m = Map<String, dynamic>.from(data);
    final items = _parseSettlementList(
      m['items'],
      SuperAdminSettlementReservation.fromMap,
    );
    final paymentItems = _parseSettlementList(
      m['payment_items'],
      SuperAdminSettlementPaymentItem.fromMap,
    );
    final cancelItems = _parseSettlementList(
      m['cancel_items'],
      SuperAdminSettlementCancelItem.fromMap,
    );

    final totalPaid = (m['total_paid'] as num?)?.toInt() ?? 0;
    final cancelRefund = (m['cancel_refund'] as num?)?.toInt() ?? 0;
    final net = (m['net_revenue'] as num?)?.toInt() ?? totalPaid;

    return SuperAdminSettlementSheet(
      totalPaid: totalPaid,
      cancelRefund: cancelRefund,
      netRevenue: net,
      paymentCount: (m['payment_count'] as num?)?.toInt() ?? 0,
      cancelCount: (m['cancel_count'] as num?)?.toInt() ?? 0,
      rentalCount: (m['rental_count'] as num?)?.toInt() ?? 0,
      isSettled: m['is_settled'] == true,
      isRequested: m['is_requested'] == true,
      items: items,
      paymentItems: paymentItems,
      cancelItems: cancelItems,
    );
  }
}

List<T> _parseSettlementList<T>(
  Object? raw,
  T Function(Map<String, dynamic> m) fromMap,
) {
  if (raw is! List) return [];
  return raw
      .map((e) => fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();
}

class SuperAdminSettlementReservation {
  final String reservationId;
  final String? reservationNumber;
  final String renterName;
  final int totalPrice;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime? rentalStartedAt;
  final DateTime? returnedAt;
  final DateTime? actualEndAt;
  final RentalType? rentalType;

  String get reservationNumberLabel {
    final number = reservationNumber?.trim();
    if (number != null && number.isNotEmpty) return number;
    final raw = reservationId.trim();
    return raw.isEmpty ? '—' : '#$raw';
  }

  const SuperAdminSettlementReservation({
    required this.reservationId,
    this.reservationNumber,
    required this.renterName,
    this.totalPrice = 0,
    this.startAt,
    this.endAt,
    this.rentalStartedAt,
    this.returnedAt,
    this.actualEndAt,
    this.rentalType,
  });

  DateTime? get displayRentalStartAt => rentalStartedAt ?? startAt;

  DateTime? get displayRentalEndAt =>
      returnedAt ?? actualEndAt ?? endAt;

  factory SuperAdminSettlementReservation.fromMap(Map<String, dynamic> m) {
    return SuperAdminSettlementReservation(
      reservationId: m['reservation_id']?.toString() ?? '',
      reservationNumber: m['reservation_number']?.toString(),
      renterName: m['renter_name']?.toString() ?? '',
      totalPrice: (m['total_price'] as num?)?.toInt() ?? 0,
      startAt: _dt(m['start_at']),
      endAt: _dt(m['end_at']),
      rentalStartedAt: _dt(m['rental_started_at']),
      returnedAt: _dt(m['returned_at']),
      actualEndAt: _dt(m['actual_end_at']),
      rentalType: RentalType.fromDb(m['rental_type']?.toString()),
    );
  }
}

class SuperAdminSettlementPaymentItem {
  final String orderId;
  final String reservationId;
  final String? reservationNumber;
  final String renterName;
  final DateTime? paidAt;
  final int paymentAmount;

  const SuperAdminSettlementPaymentItem({
    required this.orderId,
    required this.reservationId,
    this.reservationNumber,
    required this.renterName,
    this.paidAt,
    this.paymentAmount = 0,
  });

  String get reservationNumberLabel {
    final number = reservationNumber?.trim();
    if (number != null && number.isNotEmpty) return number;
    final raw = reservationId.trim();
    return raw.isEmpty ? '—' : '#$raw';
  }

  factory SuperAdminSettlementPaymentItem.fromMap(Map<String, dynamic> m) {
    return SuperAdminSettlementPaymentItem(
      orderId: m['order_id']?.toString() ?? '',
      reservationId: m['reservation_id']?.toString() ?? '',
      reservationNumber: m['reservation_number']?.toString(),
      renterName: m['renter_name']?.toString() ?? '',
      paidAt: _dt(m['paid_at']),
      paymentAmount: (m['payment_amount'] as num?)?.toInt() ?? 0,
    );
  }
}

class SuperAdminSettlementCancelItem {
  final String reservationId;
  final String? reservationNumber;
  final String renterName;
  final DateTime? cancelledAt;
  final int paidAmount;
  final int refundAmount;
  final String cancelReason;

  const SuperAdminSettlementCancelItem({
    required this.reservationId,
    this.reservationNumber,
    required this.renterName,
    this.cancelledAt,
    this.paidAmount = 0,
    this.refundAmount = 0,
    this.cancelReason = '취소',
  });

  String get reservationNumberLabel {
    final number = reservationNumber?.trim();
    if (number != null && number.isNotEmpty) return number;
    final raw = reservationId.trim();
    return raw.isEmpty ? '—' : '#$raw';
  }

  factory SuperAdminSettlementCancelItem.fromMap(Map<String, dynamic> m) {
    return SuperAdminSettlementCancelItem(
      reservationId: m['reservation_id']?.toString() ?? '',
      reservationNumber: m['reservation_number']?.toString(),
      renterName: m['renter_name']?.toString() ?? '',
      cancelledAt: _dt(m['cancelled_at']),
      paidAmount: (m['paid_amount'] as num?)?.toInt() ?? 0,
      refundAmount: (m['refund_amount'] as num?)?.toInt() ?? 0,
      cancelReason: m['cancel_reason']?.toString() ?? '취소',
    );
  }
}

class SuperAdminCoupon {
  final String id;
  final String? code;
  final String title;
  final int discountAmount;
  final int minAmount;
  final DateTime? expiresAt;
  final bool isActive;
  final int issuedCount;
  final int usedCount;
  final DateTime? createdAt;

  const SuperAdminCoupon({
    required this.id,
    this.code,
    required this.title,
    this.discountAmount = 0,
    this.minAmount = 0,
    this.expiresAt,
    this.isActive = true,
    this.issuedCount = 0,
    this.usedCount = 0,
    this.createdAt,
  });

  factory SuperAdminCoupon.fromMap(Map<String, dynamic> m) {
    return SuperAdminCoupon(
      id: m['coupon_id']?.toString() ?? m['id']?.toString() ?? '',
      code: m['code']?.toString(),
      title: m['title']?.toString() ?? '쿠폰',
      discountAmount: (m['discount_amount'] as num?)?.toInt() ?? 0,
      minAmount: (m['min_amount'] as num?)?.toInt() ?? 0,
      expiresAt: _dt(m['expires_at']),
      isActive: m['is_active'] != false,
      issuedCount: (m['issued_count'] as num?)?.toInt() ?? 0,
      usedCount: (m['used_count'] as num?)?.toInt() ?? 0,
      createdAt: _dt(m['created_at']),
    );
  }

  int get unusedCount {
    final n = issuedCount - usedCount;
    return n < 0 ? 0 : n;
  }

  bool get isMasterExpired {
    final end = expiresAt;
    if (end == null) return false;
    final today = DateTime.now();
    final endDate = DateTime(end.year, end.month, end.day);
    final todayDate = DateTime(today.year, today.month, today.day);
    return endDate.isBefore(todayDate);
  }

  String get usageSummary =>
      '발급 $issuedCount · 사용 $usedCount · 미사용 $unusedCount';
}

class BulkIssueCouponResult {
  final int issuedCount;
  final int skippedCount;
  final List<String> issuedUserIds;

  const BulkIssueCouponResult({
    this.issuedCount = 0,
    this.skippedCount = 0,
    this.issuedUserIds = const [],
  });

  factory BulkIssueCouponResult.fromMap(Map<String, dynamic> m) {
    final rawIds = m['issued_user_ids'];
    final ids = <String>[];
    if (rawIds is List) {
      for (final id in rawIds) {
        final s = id?.toString().trim() ?? '';
        if (s.isNotEmpty) ids.add(s);
      }
    }
    return BulkIssueCouponResult(
      issuedCount: (m['issued_count'] as num?)?.toInt() ?? 0,
      skippedCount: (m['skipped_count'] as num?)?.toInt() ?? 0,
      issuedUserIds: ids,
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
