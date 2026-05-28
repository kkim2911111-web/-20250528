import 'vehicle.dart';

/// 예약 + 대여·반납 정보
class Reservation {
  final String id;
  final String userId;
  final String vehicleId;
  final DateTime? startAt;
  final DateTime? endAt;
  final int totalPrice;
  final String status;
  final DateTime? rentalStartedAt;
  final DateTime? returnedAt;
  final List<String> pickupPhotos;
  final List<String> returnPhotos;
  final int? mileageStart;
  final int? mileageEnd;
  final String? fuelLevelStart;
  final String? fuelLevelEnd;
  final bool isAccident;
  final String? accidentNote;
  final Vehicle? vehicle;

  const Reservation({
    required this.id,
    required this.userId,
    required this.vehicleId,
    this.startAt,
    this.endAt,
    required this.totalPrice,
    required this.status,
    this.rentalStartedAt,
    this.returnedAt,
    this.pickupPhotos = const [],
    this.returnPhotos = const [],
    this.mileageStart,
    this.mileageEnd,
    this.fuelLevelStart,
    this.fuelLevelEnd,
    this.isAccident = false,
    this.accidentNote,
    this.vehicle,
  });

  factory Reservation.fromMap(Map<String, dynamic> map) {
    final vehicleRaw = map['vehicles'];
    Vehicle? vehicle;
    if (vehicleRaw is Map) {
      vehicle = Vehicle.fromMap(Map<String, dynamic>.from(vehicleRaw));
    }

    return Reservation(
      id: map['id'].toString(),
      userId: map['user_id']?.toString() ?? '',
      vehicleId: map['vehicle_id']?.toString() ?? '',
      startAt: _parseDate(map['start_at'] ?? map['start_time']),
      endAt: _parseDate(map['end_at'] ?? map['end_time']),
      totalPrice: (map['total_price'] as num?)?.toInt() ?? 0,
      status: map['status']?.toString() ?? 'pending',
      rentalStartedAt: _parseDate(map['rental_started_at']),
      returnedAt: _parseDate(map['returned_at']),
      pickupPhotos: _parseStringList(map['pickup_photos']),
      returnPhotos: _parseStringList(map['return_photos']),
      mileageStart: (map['mileage_start'] as num?)?.toInt(),
      mileageEnd: (map['mileage_end'] as num?)?.toInt(),
      fuelLevelStart: map['fuel_level_start']?.toString(),
      fuelLevelEnd: map['fuel_level_end']?.toString(),
      isAccident: map['is_accident'] == true,
      accidentNote: map['accident_note']?.toString(),
      vehicle: vehicle,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  static List<String> _parseStringList(Object? value) {
    if (value is List) {
      return value.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }

  bool get canStartRental => status == 'confirmed';

  bool get canReturn => status == 'in_use';

  bool get isFinished => status == 'returned' || status == 'completed';

  String get statusLabel {
    switch (status) {
      case 'pending':
        return '대기';
      case 'confirmed':
        return '예약 확정';
      case 'in_use':
        return '대여 중';
      case 'returned':
        return '반납 완료';
      case 'completed':
        return '이용 완료';
      default:
        return status;
    }
  }
}
