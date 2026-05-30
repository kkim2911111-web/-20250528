import 'package:flutter/material.dart';

import '../models/reservation.dart';
import '../screens/rental_return_screen.dart';
import '../screens/rental_start_screen.dart';
import '../screens/vehicle_use_screen.dart';
import '../theme/danji_colors.dart';

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

Future<bool?> showEarlyReturnConfirmDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: DanjiColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        EarlyReturnMessages.confirmTitle,
        style: TextStyle(
          color: DanjiColors.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: const Text(
        EarlyReturnMessages.confirmBody,
        style: TextStyle(
          color: DanjiColors.textSecondary,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

/// in_use 예약 반납 — 중도반납 시 확인 팝업 후 반납 화면
Future<T?> openRentalReturn<T>(
  BuildContext context,
  Reservation reservation,
) async {
  if (!reservation.canReturn) {
    final message = reservation.status == 'confirmed'
        ? EarlyReturnMessages.needStartRental
        : '반납할 수 없는 예약입니다. (${reservation.statusLabel})';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    return null;
  }

  final isEarlyReturn = reservation.canEarlyReturn;
  if (isEarlyReturn) {
    final confirmed = await showEarlyReturnConfirmDialog(context);
    if (confirmed != true) return null;
  }

  return Navigator.of(context).push<T>(
    MaterialPageRoute(
      builder: (_) => RentalReturnScreen(
        reservationId: reservation.id,
        isEarlyReturn: isEarlyReturn,
        earlyReturnAcknowledged: isEarlyReturn,
      ),
    ),
  );
}
