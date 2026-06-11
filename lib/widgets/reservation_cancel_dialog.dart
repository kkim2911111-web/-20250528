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
      content: _CancelConfirmBody(quote: quote, won: won),
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

class _CancelConfirmBody extends StatelessWidget {
  final CancelRefundQuote quote;
  final NumberFormat won;

  const _CancelConfirmBody({
    required this.quote,
    required this.won,
  });

  @override
  Widget build(BuildContext context) {
    final bodyStyle = DanjiTypography.bodyRegular.copyWith(
      color: DanjiColors.textSecondary,
      height: 1.5,
    );
    final tierStyle = DanjiTypography.caption.copyWith(
      color: DanjiColors.buttonBlue,
      fontWeight: FontWeight.w600,
      height: 1.4,
    );

    if (quote.paidAmount <= 0) {
      return Text(
        '결제 금액이 없습니다. 예약을 취소하시겠습니까?',
        style: bodyStyle,
      );
    }

    if (quote.isNoRefund) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('환불 불가 시점입니다.', style: bodyStyle),
          const SizedBox(height: 6),
          Text(quote.refundTierLabel, style: tierStyle),
          const SizedBox(height: 8),
          Text('취소하시겠습니까?', style: bodyStyle),
        ],
      );
    }

    final amountLine = quote.refundPercent == 100
        ? '지금 취소 시 환불 ₩${won.format(quote.refundAmount)} (전액)'
        : '지금 취소 시 환불 ₩${won.format(quote.refundAmount)} (${quote.refundPercent}%)';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(amountLine, style: bodyStyle),
        const SizedBox(height: 4),
        Text(quote.refundTierLabel, style: tierStyle),
        const SizedBox(height: 8),
        Text('정말 취소하시겠습니까?', style: bodyStyle),
      ],
    );
  }
}
