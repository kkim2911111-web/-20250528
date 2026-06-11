import 'package:danjicar_app/models/admin_timeline.dart';
import 'package:danjicar_app/utils/rental_pricing.dart';
import 'package:danjicar_app/widgets/rental_type_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rentalTypeBadgeStyle maps hourly/daily/monthly to S/R/RR', () {
    expect(rentalTypeBadgeStyle(RentalType.hourly).letter, 'S');
    expect(rentalTypeBadgeStyle(RentalType.daily).letter, 'R');
    expect(rentalTypeBadgeStyle(RentalType.monthly).letter, 'RR');
  });

  testWidgets('RentalTypeBadgeGroup shows multiple chips for S+R vehicle',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RentalTypeBadgeGroup(
            rentalTypes: [RentalType.hourly, RentalType.daily],
          ),
        ),
      ),
    );

    expect(find.text('S'), findsOneWidget);
    expect(find.text('R'), findsOneWidget);
    expect(find.text('RR'), findsNothing);
  });

  testWidgets('RentalTypeBadge shows RR for monthly reservation',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RentalTypeBadge(rentalType: RentalType.monthly),
        ),
      ),
    );

    expect(find.text('RR'), findsOneWidget);
  });

  test('AdminTimelineReservation parses rental_type from RPC map', () {
    final reservation = AdminTimelineReservation.fromMap({
      'reservation_id': 'r1',
      'vehicle_id': 'v1',
      'vehicle_name': '아반떼',
      'renter_name': '홍길동',
      'renter_phone': '010',
      'status': 'confirmed',
      'rental_type': 'daily',
    });

    expect(reservation.rentalType, RentalType.daily);
  });
}
