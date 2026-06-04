import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/rental_extension_result.dart';
import '../models/reservation.dart';
import '../services/rental_service.dart';
import '../services/support_contacts_service.dart';
import '../supabase_client.dart';
import '../theme/danji_colors.dart';
import 'phone_launcher.dart';

/// 연장 버튼 → 서버 최신 예약 조회 → 가능 여부 확인 → 연장 적용 또는 안내
Future<bool> openRentalExtension(
  BuildContext context,
  Reservation reservation, {
  int extensionHours = 1,
}) async {
  final service = RentalService();
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
                Text(RentalExtensionMessages.checking),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Reservation current;
  RentalExtensionCheckResult check;
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

    check = await service.checkRentalExtension(
      reservationId: current.id,
      extensionHours: extensionHours,
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

  if (check.eligible) {
    return _confirmAndApply(
      context,
      reservation: current,
      check: check,
      service: service,
      extensionHours: extensionHours,
    );
  }

  if (check.showEmergencyConsultation) {
    await _showEmergencyDialog(context, current, check, service);
    return false;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(_messageForExtensionCheck(check)),
    ),
  );
  return false;
}

String _messageForExtensionCheck(RentalExtensionCheckResult check) {
  switch (check.reason) {
    case 'invalid_status':
      return RentalExtensionMessages.needInUse;
    case 'too_early':
      return RentalExtensionMessages.tooEarly;
    case 'too_late':
      return RentalExtensionMessages.tooLate;
    case 'next_reservation_exists':
      return RentalExtensionMessages.nextReservationExists;
    default:
      break;
  }

  final message = check.message?.trim();
  if (message != null && message.isNotEmpty) {
    if (message.contains('종료 1시간 전부터')) {
      return RentalExtensionMessages.tooEarly;
    }
    if (message.contains('종료 시각이 지나')) {
      return RentalExtensionMessages.tooLate;
    }
    if (message.contains('in_use')) {
      return RentalExtensionMessages.needInUse;
    }
    return message;
  }
  return '지금은 연장할 수 없습니다.';
}

Future<bool> _confirmAndApply(
  BuildContext context, {
  required Reservation reservation,
  required RentalExtensionCheckResult check,
  required RentalService service,
  required int extensionHours,
}) async {
  final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  final won = NumberFormat('#,###');
  final newEnd = check.newEndAt;
  final added = check.addedPrice ?? 0;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: DanjiColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        RentalExtensionMessages.confirmTitle,
        style: TextStyle(
          color: DanjiColors.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Text(
        [
          '${extensionHours}시간 연장합니다.',
          if (newEnd != null) '새 종료 시각: ${dateFormat.format(newEnd)}',
          '추가 요금: ₩${won.format(added)}',
          if (check.newTotalPrice != null)
            '결제 합계: ₩${won.format(check.newTotalPrice)}',
          if (added > 0) '등록된 결제카드로 자동 결제됩니다.',
        ].join('\n'),
        style: const TextStyle(
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
          child: const Text('연장하기'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return false;

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

  final reservationId = reservation.id;
  final addedPrice = added;

  try {
    await service.payAndApplyRentalExtension(
      reservationId: reservationId,
      extensionHours: extensionHours,
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

  debugPrint(
    '[extension/points] extension payment ok — '
    'reservationId=$reservationId, addedPrice=$addedPrice',
  );
  if (addedPrice > 0) {
    final user = supabase.auth.currentUser;
    if (user == null) {
      debugPrint('[extension/points] skip — not logged in');
    } else {
      try {
        await supabase.rpc('grant_extension_points', params: {
          'p_user_id': user.id,
          'p_reservation_id': reservationId,
          'p_amount': addedPrice,
        });
        debugPrint('[extension/points] grant_extension_points ok');
      } catch (e) {
        debugPrint('[extension/points] grant_extension_points failed: $e');
      }
    }
  } else {
    debugPrint('[extension/points] skip — addedPrice is 0');
  }

  if (navigator.canPop()) navigator.pop();
  if (!context.mounted) return false;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text(RentalExtensionMessages.success)),
  );
  return true;
}

Future<void> _showEmergencyDialog(
  BuildContext context,
  Reservation reservation,
  RentalExtensionCheckResult check,
  RentalService service,
) async {
  var phone = SupportContactsService.normalizePhone(check.emergencyPhone);
  phone ??= await SupportContactsService().fetchEmergencyPhone();
  if (!context.mounted) return;

  if (phone == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('긴급 상담 번호가 등록되지 않았습니다. 관리자에게 문의해주세요.'),
      ),
    );
    return;
  }
  final phoneNumber = phone;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: DanjiColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        RentalExtensionMessages.emergencyTitle,
        style: TextStyle(
          color: DanjiColors.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Text(
        () {
          final msg = _messageForExtensionCheck(check);
          if (msg.isNotEmpty && msg != '지금은 연장할 수 없습니다.') return msg;
          return RentalExtensionMessages.nextReservationExists;
        }(),
        style: const TextStyle(
          color: DanjiColors.textSecondary,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('닫기'),
        ),
        FilledButton.icon(
          onPressed: () async {
            try {
              await service.logEmergencyConsultation(
                reservationId: reservation.id,
                requestType: 'extension_blocked',
                reasonCode: check.reason,
                context: check.toLogContext(),
              );
            } catch (_) {}

            final launched = await launchPhoneCall(phoneNumber);
            if (!ctx.mounted) return;
            if (!launched) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text('전화 연결: $phoneNumber')),
              );
            }
            Navigator.of(ctx).pop();
          },
          icon: const Icon(Icons.phone),
          label: Text('긴급 상담 ($phoneNumber)'),
        ),
      ],
    ),
  );
}

String _friendlyError(Object error) {
  return error.toString().replaceFirst('RentalException: ', '');
}
