import 'package:danjicar_app/models/vehicle.dart';
import 'package:danjicar_app/utils/rental_pricing.dart';
import 'package:danjicar_app/utils/vehicle_rental_type_price_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildVehicleRentalTypePriceLines', () {
    test('월렌트 전용 — 시간 요금 숨김', () {
      const vehicle = Vehicle(
        id: '1',
        complexId: 'c1',
        name: '카니발9',
        vehicleType: 'SUV',
        pricePerHour: 0,
        monthlyPrice: 1100000,
        monthlyExcessDailyPrice: 110000,
        rentalTypes: [RentalType.monthly],
        isAvailable: true,
      );

      final lines = buildVehicleRentalTypePriceLines(vehicle);
      expect(lines.length, 1);
      expect(lines.first, '월 ₩1,100,000 · 초과 일요금 ₩110,000');
    });

    test('복수 유형 — 활성 유형별 한 줄', () {
      const vehicle = Vehicle(
        id: '2',
        complexId: 'c1',
        name: '아반떼',
        vehicleType: '세단',
        pricePerHour: 5000,
        dailyPrice: 80000,
        rentalTypes: [RentalType.hourly, RentalType.daily],
        isAvailable: true,
      );

      final lines = buildVehicleRentalTypePriceLines(vehicle);
      expect(lines, ['시간 ₩5,000/h', '일 ₩80,000']);
    });
  });
}
