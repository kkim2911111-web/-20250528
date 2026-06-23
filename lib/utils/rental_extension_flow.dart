import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_feature_config.dart';
import '../models/rental_extension_result.dart';
import '../models/reservation.dart';
import '../models/vehicle.dart';
import '../services/next_reservation_service.dart';
import '../services/rental_service.dart';
import '../supabase_client.dart';
import '../theme/danji_colors.dart';
import '../utils/feature_kill_switch_guard.dart';
import '../widgets/rental_extension_sheet.dart';

/// 연장 버튼 → 바텀시트 → 결제·적용
Future<bool> openRentalExtension(
  BuildContext context,
  Reservation reservation,
) async {
  if (!await ensureFeatureEnabled(context, AppFeatureKeys.extension)) {
    return false;
  }

  final service = RentalService();
  final nextService = NextReservationService();
  final navigator = Navigator.of(context, rootNavigator: true);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(RentalExtensionMessages.loading),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Reservation current;
  Vehicle vehicle;
  NextBlockingReservation? nextReservation;

  try {
    current = await service.fetchReservation(reservation.id);
    if (!current.isInUse) {
      if (navigator.canPop()) navigator.pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(RentalExtensionMessages.needInUse)),
        );
      }
      return false;
    }

    final endAt = current.endAt;
    if (endAt == null) {
      if (navigator.canPop()) navigator.pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('종료 시각을 확인할 수 없습니다.')),
        );
      }
      return false;
    }

    final vehicleRow = await supabase
        .from('vehicles')
        .select(
          'id, model_name, price_per_hour, daily_overage_hourly_rate, '
          'monthly_excess_daily_price, rental_types, vehicle_type',
        )
        .eq('id', current.vehicleId)
        .maybeSingle();

    if (vehicleRow == null) {
      if (navigator.canPop()) navigator.pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('차량 정보를 불러올 수 없습니다.')),
        );
      }
      return false;
    }

    vehicle = Vehicle.fromMap(Map<String, dynamic>.from(vehicleRow));
    nextReservation = await nextService.fetchNextBlockingReservation(
      vehicleId: current.vehicleId,
      afterEndAt: endAt,
      excludeReservationId: current.id,
    );
  } catch (e) {
    if (navigator.canPop()) navigator.pop();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    }
    return false;
  }

  if (navigator.canPop()) navigator.pop();
  if (!context.mounted) return false;

  final selectedNewEnd = await showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: DanjiColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => RentalExtensionSheet(
      reservation: current,
      vehicle: vehicle,
      nextReservation: nextReservation,
    ),
  );

  if (selectedNewEnd == null || !context.mounted) return false;

  return _payAndApply(
    context,
    service: service,
    reservation: current,
    newEndAt: selectedNewEnd,
  );
}

Future<bool> _payAndApply(
  BuildContext context, {
  required RentalService service,
  required Reservation reservation,
  required DateTime newEndAt,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(RentalExtensionMessages.payingAndApplying),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  try {
    await service.payAndApplyRentalExtension(
      reservationId: reservation.id,
      newEndAt: newEndAt,
    );
  } catch (e) {
    if (navigator.canPop()) navigator.pop();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    }
    return false;
  }

  if (navigator.canPop()) navigator.pop();
  if (!context.mounted) return false;

  final fmt = DateFormat('HH:mm');
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '${RentalExtensionMessages.success} (종료 ${fmt.format(newEndAt)})',
      ),
    ),
  );
  return true;
}

String _friendlyError(Object error) {
  return error.toString().replaceFirst('RentalException: ', '');
}
