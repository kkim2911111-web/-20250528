import 'package:flutter/material.dart';

import '../models/reservation.dart';
import '../screens/rental_return_screen.dart';
import '../screens/rental_start_screen.dart';

/// 대여하기 — 항상 [RentalStartScreen] (사진 → 면허 → 문열림)
Future<T?> openRentalOrUseScreen<T>(
  BuildContext context,
  Reservation reservation,
) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute(
      builder: (_) => RentalStartScreen(reservationId: reservation.id),
    ),
  );
}

/// in_use 예약 반납
Future<T?> openRentalReturn<T>(
  BuildContext context,
  Reservation reservation,
) {
  if (!reservation.canReturn) {
    final message = reservation.status == 'confirmed'
        ? '대여 시작 후 반납할 수 있습니다.\n대여하기 화면에서 대여를 시작해주세요.'
        : '반납할 수 없는 예약입니다. (${reservation.statusLabel})';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    return Future.value(null);
  }

  return Navigator.of(context).push<T>(
    MaterialPageRoute(
      builder: (_) => RentalReturnScreen(reservationId: reservation.id),
    ),
  );
}
