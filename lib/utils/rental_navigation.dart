import 'package:flutter/material.dart';

import '../models/reservation.dart';
import '../screens/rental_start_screen.dart';
import '../screens/vehicle_use_screen.dart';

/// 대여 시작(대기) → RentalStartScreen, 이용 중 → VehicleUseScreen
Future<T?> openRentalOrUseScreen<T>(
  BuildContext context,
  Reservation reservation,
) {
  if (reservation.status == 'in_use') {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(
        builder: (_) => VehicleUseScreen(reservationId: reservation.id),
      ),
    );
  }

  return Navigator.of(context).push<T>(
    MaterialPageRoute(
      builder: (_) => RentalStartScreen(reservationId: reservation.id),
    ),
  );
}
