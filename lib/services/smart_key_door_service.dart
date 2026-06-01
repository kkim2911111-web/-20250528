import 'package:flutter/material.dart';

import '../theme/danji_colors.dart';
import 'rental_service.dart';
import 'reservation_schema_service.dart';

/// 스마트키 도어 제어 — Supabase RPC / door_unlocked 컬럼
class SmartKeyDoorService {
  SmartKeyDoorService({RentalService? rentalService})
      : _rentalService = rentalService ?? RentalService();

  final RentalService _rentalService;

  Future<bool> setDoorLock({
    required String reservationId,
    required bool unlocked,
    BuildContext? context,
  }) async {
    if (!ReservationSchemaService.isDoorColumnAvailable) {
      if (context != null && context.mounted) {
        await SmartKeyDoorFeedback.showSchemaError(context);
      }
      throw const RentalException(
        ReservationSchemaService.doorColumnMissingMessage,
      );
    }

    return _setDoorLockLive(
      reservationId: reservationId,
      unlocked: unlocked,
      context: context,
    );
  }

  Future<bool> _setDoorLockLive({
    required String reservationId,
    required bool unlocked,
    BuildContext? context,
  }) async {
    try {
      return await _rentalService.setDoorLock(
        reservationId: reservationId,
        unlocked: unlocked,
      );
    } catch (e) {
      if (_isSchemaError(e)) {
        if (context != null && context.mounted) {
          await SmartKeyDoorFeedback.showSchemaError(context);
        }
        throw RentalException(_schemaMessage(e));
      }
      rethrow;
    }
  }

  static bool _isSchemaError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('door_unlocked') ||
        msg.contains('does not exist') ||
        msg.contains('42703') ||
        msg.contains('could not find the function') ||
        msg.contains('schema cache') ||
        msg.contains('fix_reservations_schema');
  }

  static String _schemaMessage(Object error) {
    if (_isSchemaError(error)) {
      return ReservationSchemaService.doorColumnMissingMessage;
    }
    return error.toString().replaceFirst('RentalException: ', '');
  }
}

/// 문열림/문닫힘 결과 팝업
abstract final class SmartKeyDoorFeedback {
  static const unlockMessage = '차량 문이 열렸습니다.';
  static const lockMessage = '차량 문이 닫혔습니다.';

  static Future<void> showUnlockSuccess(BuildContext context) {
    return _showDialog(
      context,
      title: '문열림',
      message: unlockMessage,
    );
  }

  static Future<void> showLockSuccess(BuildContext context) {
    return _showDialog(
      context,
      title: '문닫힘',
      message: lockMessage,
    );
  }

  static Future<void> showSchemaError(BuildContext context) {
    return _showDialog(
      context,
      title: '차량 제어 설정 필요',
      message: ReservationSchemaService.doorColumnMissingMessage,
      isError: true,
    );
  }

  static Future<void> showResult(
    BuildContext context, {
    required bool unlocked,
  }) {
    return unlocked
        ? showUnlockSuccess(context)
        : showLockSuccess(context);
  }

  static Future<void> _showDialog(
    BuildContext context, {
    required String title,
    required String message,
    bool isError = false,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: DanjiColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: TextStyle(
            color: isError ? DanjiColors.accentRed : DanjiColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: DanjiColors.textSecondary,
            height: 1.45,
            fontSize: 15,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: FilledButton.styleFrom(
              backgroundColor:
                  isError ? DanjiColors.accentRed : DanjiColors.rentalBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}
