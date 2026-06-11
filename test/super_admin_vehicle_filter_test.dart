import 'package:danjicar_app/models/super_admin_models.dart';
import 'package:danjicar_app/screens/super_admin/super_admin_nav.dart';
import 'package:danjicar_app/utils/rental_pricing.dart';
import 'package:danjicar_app/utils/super_admin_vehicle_filter.dart';
import 'package:flutter_test/flutter_test.dart';

SuperAdminVehicle _vehicle({
  required String id,
  bool isAvailable = true,
  bool inUse = false,
  int pricePerHour = 0,
  int? monthlyPrice,
  List<RentalType> rentalTypes = const [RentalType.hourly],
}) {
  return SuperAdminVehicle(
    id: id,
    complexId: 'c1',
    complexName: '단지',
    modelName: '차량$id',
    pricePerHour: pricePerHour,
    monthlyPrice: monthlyPrice,
    rentalTypes: rentalTypes,
    isAvailable: isAvailable,
    inUse: inUse,
  );
}

void main() {
  group('applySuperAdminVehicleFilter', () {
    final list = [
      _vehicle(id: '1', isAvailable: true, inUse: false),
      _vehicle(id: '2', isAvailable: false, inUse: false),
      _vehicle(id: '3', isAvailable: true, inUse: true),
    ];

    test('available tab — 가용·비대여만', () {
      final filtered = applySuperAdminVehicleFilter(
        list: list,
        filter: SuperAdminVehicleFilter.available,
      );
      expect(filtered.map((v) => v.id).toList(), ['1']);
    });

    test('inUse tab — 대여중만', () {
      final filtered = applySuperAdminVehicleFilter(
        list: list,
        filter: SuperAdminVehicleFilter.inUse,
      );
      expect(filtered.map((v) => v.id).toList(), ['3']);
    });

    test('toggle off is_available excludes from available', () {
      final filtered = applySuperAdminVehicleFilter(
        list: [
          _vehicle(id: '1', isAvailable: true),
          _vehicle(id: '2', isAvailable: false),
        ],
        filter: SuperAdminVehicleFilter.available,
      );
      expect(filtered.length, 1);
      expect(filtered.first.id, '1');
    });
  });

  group('cardUnitPriceLabel super admin monthly', () {
    test('hourly default + monthly_price → ₩N/월', () {
      expect(
        RentalPricing.cardUnitPriceLabel(
          pricePerHour: 0,
          monthlyPrice: 1100000,
          rentalTypes: const [RentalType.hourly],
        ),
        '₩1,100,000/월',
      );
    });

    test('does not show ₩0/시간 for monthly-only legacy row', () {
      final label = RentalPricing.cardUnitPriceLabel(
        pricePerHour: 0,
        monthlyPrice: 1100000,
        rentalTypes: const [],
      );
      expect(label, isNot(contains('/h')));
      expect(label, contains('/월'));
    });
  });
}
