import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/rental_extension_result.dart';
import '../models/reservation.dart';
import '../services/rental_service.dart';
import '../theme/danji_colors.dart';
import 'phone_launcher.dart';

/// 연장 버튼 → 가능 여부 확인 → 연장 적용 또는 긴급 상담 안내
Future<bool> openRentalExtension(
  BuildContext context,
  Reservation reservation, {
  int extensionHours = 1,
}) async {
  if (reservation.status != 'in_use') {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(RentalExtensionMessages.needInUse)),
    );
    return false;
  }

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

  RentalExtensionCheckResult check;
  try {
    check = await service.checkRentalExtension(
      reservationId: reservation.id,
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
      reservation: reservation,
      check: check,
      service: service,
      extensionHours: extensionHours,
    );
  }

  if (check.showEmergencyConsultation) {
    await _showEmergencyDialog(context, reservation, check, service);
    return false;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(check.message ?? '지금은 연장할 수 없습니다.'),
    ),
  );
  return false;
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
                Text(RentalExtensionMessages.applying),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  try {
    await service.applyRentalExtension(
      reservationId: reservation.id,
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
  final phone = check.emergencyPhone ?? '010-4455-6676';

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
        check.message ??
            '다음 예약이 있어 연장할 수 없습니다.\n긴급 상담으로 문의해주세요.',
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

            final launched = await launchPhoneCall(phone);
            if (!ctx.mounted) return;
            if (!launched) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text('전화 연결: $phone')),
              );
            }
            Navigator.of(ctx).pop();
          },
          icon: const Icon(Icons.phone),
          label: Text('긴급 상담 ($phone)'),
        ),
      ],
    ),
  );
}

String _friendlyError(Object error) {
  return error.toString().replaceFirst('RentalException: ', '');
}
