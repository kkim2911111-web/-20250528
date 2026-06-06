class Vehicle {
  final String id;
  final String complexId;
  final String name;
  final String vehicleType;
  final int pricePerHour;
  final String? parkingLocation;
  final String? parkingPhotoUrl;
  final String? carImageUrl;
  final String? carNumber;
  final bool isAvailable;

  const Vehicle({
    required this.id,
    required this.complexId,
    required this.name,
    required this.vehicleType,
    required this.pricePerHour,
    this.parkingLocation,
    this.parkingPhotoUrl,
    this.carImageUrl,
    this.carNumber,
    required this.isAvailable,
  });

  factory Vehicle.fromMap(Map<String, dynamic> map) {
    final available = map['is_available'] as bool? ??
        map['is_active'] as bool? ??
        true;

    return Vehicle(
      id: map['id'].toString(),
      complexId: map['complex_id']?.toString() ?? '',
      name: _readString(map, ['model_name', 'car_name', 'model']) ?? '차량',
      vehicleType: _readString(map, ['vehicle_type', 'car_type', 'type']) ?? '기타',
      pricePerHour: (map['price_per_hour'] as num?)?.toInt() ??
          (map['hourly_rate'] as num?)?.toInt() ??
          0,
      parkingLocation: _readString(map, ['parking_location', 'parking_spot']),
      parkingPhotoUrl: _readString(map, ['parking_photo_url', 'photo_url']),
      carImageUrl: _readString(map, ['car_image_url']),
      carNumber: _readString(map, ['car_number', 'plate_number']),
      isAvailable: available,
    );
  }

  static String? _readString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

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