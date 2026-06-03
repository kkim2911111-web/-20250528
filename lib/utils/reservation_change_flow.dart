import 'package:flutter/material.dart';

import '../models/reservation.dart';
import '../models/vehicle.dart';
import '../screens/reservation_screen.dart';
import '../supabase_client.dart';

/// 예약 변경 화면(ReservationScreen 수정 모드)으로 이동
Future<bool> openReservationChange(
  BuildContext context,
  Reservation reservation,
) async {
  if (!reservation.canChangeReservation) {
    if (reservation.isChangeBlocked && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(ReservationCancelMessages.changeTooLate),
        ),
      );
    }
    return false;
  }

  final vehicle = await _resolveVehicle(reservation);
  if (vehicle == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('차량 정보를 불러올 수 없습니다.')),
      );
    }
    return false;
  }

  if (!context.mounted) return false;

  final changed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => ReservationScreen(
        vehicle: vehicle,
        existingReservation: reservation,
      ),
    ),
  );

  return changed == true;
}

Future<Vehicle?> _resolveVehicle(Reservation reservation) async {
  if (reservation.vehicle != null) return reservation.vehicle;

  try {
    final row = await supabase
        .from('vehicles')
        .select(
          'id, complex_id, model_name, vehicle_type, price_per_hour, '
          'hourly_rate, parking_location, car_number, is_available, is_active',
        )
        .eq('id', reservation.vehicleId)
        .maybeSingle();

    if (row == null) return null;
    return Vehicle.fromMap(Map<String, dynamic>.from(row));
  } catch (_) {
    return null;
  }
}

/// 홈·내 예약 — 예약 변경/취소 선택 다이얼로그
Future<void> showReservationManageDialog({
  required BuildContext context,
  required Reservation reservation,
  required Future<void> Function() onCancel,
  required Future<void> Function() onChange,
}) async {
  if (reservation.isChangeBlocked) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(ReservationCancelMessages.changeTooLate)),
    );
    return;
  }

  if (!reservation.canCancel && !reservation.canChangeReservation) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('변경·취소할 수 없는 예약입니다.')),
    );
    return;
  }

  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Theme.of(ctx).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '예약 변경/취소',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: const Text(
        '원하시는 작업을 선택해주세요.',
        style: TextStyle(height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('닫기'),
        ),
        if (reservation.canChangeReservation)
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'change'),
            child: const Text('예약 변경'),
          ),
        if (reservation.canCancel)
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('예약 취소'),
          ),
      ],
    ),
  );

  if (action == 'change') {
    await onChange();
  } else if (action == 'cancel') {
    await onCancel();
  }
}
