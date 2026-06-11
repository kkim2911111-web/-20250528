import '../utils/rental_pricing.dart';

class AdminCustomer {
  final String userId;
  final String fullName;
  final String phone;
  final String? building;
  final String? unit;
  final int rentalCount;
  final int totalPayment;
  final DateTime? lastUsedAt;
  final bool isBlacklisted;
  final DateTime? joinedAt;
  final DateTime? lastRentalAt;

  const AdminCustomer({
    required this.userId,
    required this.fullName,
    required this.phone,
    this.building,
    this.unit,
    required this.rentalCount,
    required this.totalPayment,
    this.lastUsedAt,
    required this.isBlacklisted,
    this.joinedAt,
    this.lastRentalAt,
  });

  String get unitLabel {
    final b = building?.trim();
    final u = unit?.trim();
    if (b != null && b.isNotEmpty && u != null && u.isNotEmpty) {
      return '$b동 $u호';
    }
    if (b != null && b.isNotEmpty) return '$b동';
    if (u != null && u.isNotEmpty) return '$u호';
    return '동·호 미등록';
  }

  factory AdminCustomer.fromMap(Map<String, dynamic> map) {
    return AdminCustomer(
      userId: map['user_id']?.toString() ?? '',
      fullName: map['full_name']?.toString() ?? '이름 미등록',
      phone: map['phone']?.toString() ?? '',
      building: map['building']?.toString(),
      unit: map['unit']?.toString(),
      rentalCount: (map['rental_count'] as num?)?.toInt() ?? 0,
      totalPayment: (map['total_payment'] as num?)?.toInt() ?? 0,
      lastUsedAt: _parseDateTime(map['last_used_at']),
      isBlacklisted: map['is_blacklisted'] == true,
      joinedAt: _parseDateTime(map['joined_at']),
      lastRentalAt: _parseDateTime(map['last_rental_at']),
    );
  }

  static DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw.toString());
  }
}

class AdminCustomerReservation {
  final String reservationId;
  final String vehicleName;
  final String? carNumber;
  final String status;
  final DateTime? startAt;
  final DateTime? endAt;
  final int totalPrice;
  final DateTime? returnCompletedAt;
  final RentalType? rentalType;

  const AdminCustomerReservation({
    required this.reservationId,
    required this.vehicleName,
    this.carNumber,
    required this.status,
    this.startAt,
    this.endAt,
    required this.totalPrice,
    this.returnCompletedAt,
    this.rentalType,
  });

  factory AdminCustomerReservation.fromMap(Map<String, dynamic> map) {
    return AdminCustomerReservation(
      reservationId: map['reservation_id']?.toString() ?? '',
      vehicleName: map['vehicle_name']?.toString() ?? '차량',
      carNumber: map['car_number']?.toString(),
      status: map['status']?.toString() ?? '',
      startAt: _parseDateTime(map['start_at']),
      endAt: _parseDateTime(map['end_at']),
      totalPrice: (map['total_price'] as num?)?.toInt() ?? 0,
      returnCompletedAt: _parseDateTime(map['return_completed_at']),
      rentalType: RentalType.fromDb(map['rental_type']?.toString()),
    );
  }

  static DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw.toString());
  }

  String get statusLabel {
    switch (status) {
      case 'pending':
        return '결제대기';
      case 'confirmed':
        return '예약확정';
      case 'in_use':
        return '이용중';
      case 'completed':
        return '완료';
      case 'cancelled':
        return '취소';
      default:
        return status;
    }
  }
}
