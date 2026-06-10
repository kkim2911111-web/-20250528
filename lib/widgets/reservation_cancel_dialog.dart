import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/danji_colors.dart';
import '../theme/danji_theme.dart';
import '../theme/danji_typography.dart';
import '../utils/cancel_refund_policy.dart';

Future<bool> showReservationCancelConfirmDialog(
  BuildContext context, {
  required CancelRefundQuote quote,
}) {
  final won = NumberFormat('#,###');
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: DanjiColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        '예약 취소',
        style: DanjiTypography.subtitleLarge.copyWith(
          color: DanjiColors.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Text(
        quote.confirmMessage(won: won),
        style: DanjiTypography.bodyRegular.copyWith(
          color: DanjiColors.textSecondary,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('닫기'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: DanjiTheme.dangerButton,
          child: const Text('예약취소'),
        ),
      ],
    ),
  ).then((value) => value == true);
}
