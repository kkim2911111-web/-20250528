import 'package:flutter/material.dart';

import 'rental_start_screen.dart';

/// @deprecated [RentalStartScreen]으로 통합됨. 직접 사용하지 말고 [openRentalOrUseScreen] 사용.
@Deprecated('RentalStartScreen / openRentalOrUseScreen 을 사용하세요.')
class VehicleUseScreen extends StatelessWidget {
  final String reservationId;

  const VehicleUseScreen({super.key, required this.reservationId});

  @override
  Widget build(BuildContext context) {
    return RentalStartScreen(reservationId: reservationId);
  }
}
