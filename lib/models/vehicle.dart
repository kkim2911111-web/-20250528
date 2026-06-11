import '../utils/rental_pricing.dart';
import '../utils/vehicle_insurance_status.dart';

class Vehicle {
  final String id;
  final String complexId;
  final String name;
  final String vehicleType;
  final String serviceType;
  final int pricePerHour;
  final int? dailyPrice;
  final int? monthlyPrice;
  final int? monthlyExcessDailyPrice;
  final List<RentalType> rentalTypes;
  final String? parkingLocation;
  final String? parkingPhotoUrl;
  final String? carImageUrl;
  final String? carNumber;
  final bool isPublished;
  final bool isAvailable;
  final int totalMileage;
  final bool isUnderMaintenance;
  final String? maintenanceMemo;
  final DateTime? insuranceExpiresAt;

  const Vehicle({
    required this.id,
    required this.complexId,
    required this.name,
    required this.vehicleType,
    this.serviceType = VehicleServiceType.sharing,
    required this.pricePerHour,
    this.dailyPrice,
    this.monthlyPrice,
    this.monthlyExcessDailyPrice,
    this.rentalTypes = const [RentalType.hourly],
    this.parkingLocation,
    this.parkingPhotoUrl,
    this.carImageUrl,
    this.carNumber,
    this.isPublished = false,
    required this.isAvailable,
    this.totalMileage = 0,
    this.isUnderMaintenance = false,
    this.maintenanceMemo,
    this.insuranceExpiresAt,
  });

  bool get isResidentBookable => VehicleInsuranceStatus.isResidentBookable(
        isPublished: isPublished,
        isUnderMaintenance: isUnderMaintenance,
        insuranceExpiresAt: insuranceExpiresAt,
      );

  factory Vehicle.fromMap(Map<String, dynamic> map) {
    final published = map['is_published'] as bool? ??
        map['is_available'] as bool? ??
        map['is_active'] as bool? ??
        false;
    final available = map['is_available'] as bool? ??
        map['is_active'] as bool? ??
        true;
    final rentalTypes = RentalPricing.parseRentalTypes(map['rental_types']);

    return Vehicle(
      id: map['id'].toString(),
      complexId: map['complex_id']?.toString() ?? '',
      name: _readString(map, ['model_name', 'car_name', 'model']) ?? '차량',
      vehicleType: RentalPricing.parseCarCategory(map) ?? '기타',
      serviceType: RentalPricing.parseServiceType(
        map['vehicle_type'],
        rentalTypes: rentalTypes,
      ),
      pricePerHour: (map['price_per_hour'] as num?)?.toInt() ??
          (map['hourly_rate'] as num?)?.toInt() ??
          0,
      dailyPrice: (map['daily_price'] as num?)?.toInt(),
      monthlyPrice: (map['monthly_price'] as num?)?.toInt(),
      monthlyExcessDailyPrice:
          (map['monthly_excess_daily_price'] as num?)?.toInt(),
      rentalTypes: rentalTypes,
      parkingLocation: _readString(map, ['parking_location', 'parking_spot']),
      parkingPhotoUrl: _readString(map, ['parking_photo_url', 'photo_url']),
      carImageUrl: _readString(map, ['car_image_url']),
      carNumber: _readString(map, ['car_number', 'plate_number']),
      isPublished: published,
      isAvailable: available,
      totalMileage: (map['total_mileage'] as num?)?.toInt() ?? 0,
      isUnderMaintenance: map['is_under_maintenance'] == true,
      maintenanceMemo: _readString(map, ['maintenance_memo']),
      insuranceExpiresAt: _parseDate(map['insurance_expires_at']),
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  static String? _readString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  bool supportsRentalType(RentalType type) => rentalTypes.contains(type);

  bool get isSharingService => serviceType == VehicleServiceType.sharing;

  bool get isRentalService => serviceType == VehicleServiceType.rental;

  String get priceLabel {
    final formatted = _formatWon(pricePerHour);
    return '$formatted/시간';
  }

  static String _formatWon(int amount) {
    final s = amount.toString();
    final buf = StringBuffer('₩');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
