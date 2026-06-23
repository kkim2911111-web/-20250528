import 'package:flutter_test/flutter_test.dart';

import 'package:danjicar_app/models/vehicle.dart';
import 'package:danjicar_app/utils/rental_extension_pricing.dart';
import 'package:danjicar_app/utils/rental_pricing.dart';

Vehicle _vehicle({
  int pricePerHour = 10000,
  int? dailyOverage = 5000,
  int? monthlyExcess = 30000,
}) {
  return Vehicle(
    id: 'v1',
    name: 'Test',
    complexId: 'c1',
    vehicleType: 'sedan',
    pricePerHour: pricePerHour,
    dailyOverageHourlyRate: dailyOverage,
    monthlyExcessDailyPrice: monthlyExcess,
    rentalTypes: const [RentalType.hourly],
    serviceType: 'sharing',
    isPublished: true,
    isAvailable: true,
    insuranceExpiresAt: DateTime.now().add(const Duration(days: 30)),
  );
}

void main() {
  final currentEnd = DateTime(2026, 6, 22, 14, 0);

  test('hourly extension price rounds up to full hours', () {
    final price = RentalExtensionPricing.addedPrice(
      rentalType: RentalType.hourly,
      currentEnd: currentEnd,
      newEnd: currentEnd.add(const Duration(minutes: 70)),
      vehicle: _vehicle(pricePerHour: 10000),
    );
    expect(price, 20000);
  });

  test('daily extension uses daily overage rate per day', () {
    final price = RentalExtensionPricing.addedPrice(
      rentalType: RentalType.daily,
      currentEnd: currentEnd,
      newEnd: currentEnd.add(const Duration(days: 2)),
      vehicle: _vehicle(dailyOverage: 5000),
    );
    expect(price, 10000);
  });

  test('monthly extension uses monthly excess daily price', () {
    final price = RentalExtensionPricing.addedPrice(
      rentalType: RentalType.monthly,
      currentEnd: currentEnd,
      newEnd: currentEnd.add(const Duration(days: 30)),
      vehicle: _vehicle(monthlyExcess: 20000),
    );
    expect(price, 600000);
  });

  test('preset new end for hourly adds hours', () {
    final newEnd = RentalExtensionPricing.newEndForPreset(
      rentalType: RentalType.hourly,
      currentEnd: currentEnd,
      presetValue: 3,
    );
    expect(newEnd, currentEnd.add(const Duration(hours: 3)));
  });
}
