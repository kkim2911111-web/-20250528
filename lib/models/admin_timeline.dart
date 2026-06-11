import '../utils/rental_pricing.dart';
import '../utils/reservation_display.dart';
import 'staff_profile.dart';

class AdminTimelineReservation {
  final String id;
  final String? reservationNumber;
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
  final int totalPrice;
  final RentalType? rentalType;

  const AdminTimelineReservation({
    required this.id,
    this.reservationNumber,
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
    this.totalPrice = 0,
    this.rentalType,
  });

  String get reservationNumberLabel => resolveReservationNumberLabel(
        reservationNumber: reservationNumber,
        rawId: id,
      );

  String get displayStatusKey {
    if (isNoShow) return 'no_show';
    return status.trim().toLowerCase();
  }

  factory AdminTimelineReservation.fromMap(Map<String, dynamic> m) {
    DateTime? dt(Object? v) =>
        DateTime.tryParse(v?.toString() ?? '')?.toLocal();

    return AdminTimelineReservation(
      id: m['reservation_id']?.toString() ?? m['id']?.toString() ?? '',
      reservationNumber: m['reservation_number']?.toString(),
      vehicleId: m['vehicle_id']?.toString() ?? '',
      vehicleName: m['vehicle_name']?.toString() ?? '차량',
      carNumber: m['car_number']?.toString(),
      renterName: AdminReservationRow.resolveRenterDisplayName(
        directRenterName: m['renter_name']?.toString(),
      ),
      renterPhone: m['renter_phone']?.toString() ?? '미등록',
      status: m['status']?.toString() ?? '',
      isNoShow: m['is_no_show'] == true,
      startAt: dt(m['start_at']),
      endAt: dt(m['end_at']),
      rentalStartedAt: dt(m['rental_started_at']),
      returnedAt: dt(m['returned_at']),
      totalPrice: (m['total_price'] as num?)?.toInt() ?? 0,
      rentalType: RentalType.fromDb(m['rental_type']?.toString()),
    );
  }
}

class AdminReservationTimelineData {
  final List<AdminVehicleDetail> vehicles;
  final List<AdminTimelineReservation> reservations;

  const AdminReservationTimelineData({
    required this.vehicles,
    required this.reservations,
  });
}
