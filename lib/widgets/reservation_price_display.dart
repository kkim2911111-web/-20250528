import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/reservation_payment_pricing.dart';
import '../theme/danji_colors.dart';
import '../theme/danji_typography.dart';

/// 예약 카드 — 금액(할인 전/후) 표시
class ReservationPriceDisplay extends StatelessWidget {
  final int reservationTotalPrice;
  final ReservationPaymentPricing? pricing;
  final NumberFormat won;
  final TextStyle? priceStyle;

  const ReservationPriceDisplay({
    super.key,
    required this.reservationTotalPrice,
    required this.pricing,
    required this.won,
    this.priceStyle,
  });

  @override
  Widget build(BuildContext context) {
    final displayPrice = pricing?.finalPrice ?? reservationTotalPrice;
    if (displayPrice <= 0) return const SizedBox.shrink();

    final style = priceStyle ??
        DanjiTypography.body.copyWith(fontWeight: FontWeight.w600);

    if (pricing == null || !pricing!.hasDiscount) {
      return Text('₩${won.format(displayPrice)}', style: style);
    }

    final p = pricing!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '₩${won.format(p.originalPrice)}',
          style: style.copyWith(
            fontSize: (style.fontSize ?? 14) * 0.92,
            fontWeight: FontWeight.w500,
            color: DanjiColors.textSecondary,
            decoration: TextDecoration.lineThrough,
            decorationColor: DanjiColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('₩${won.format(p.finalPrice)}', style: style),
            if (p.discountBadge.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                p.discountBadge,
                style: DanjiTypography.caption.copyWith(
                  color: DanjiColors.buttonBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
