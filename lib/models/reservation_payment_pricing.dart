/// 예약 카드 금액 표시용 payment_orders 할인 정보
class ReservationPaymentPricing {
  final int originalPrice;
  final int finalPrice;
  final bool hasCoupon;
  final bool hasPoints;

  const ReservationPaymentPricing({
    required this.originalPrice,
    required this.finalPrice,
    required this.hasCoupon,
    required this.hasPoints,
  });

  bool get hasDiscount => hasCoupon || hasPoints;

  /// 쿠폰·포인트·둘 다 — 카드 하단 배지 텍스트
  String get discountBadge {
    if (hasCoupon && hasPoints) return '🎟️💰';
    if (hasCoupon) return '🎟️ 쿠폰 할인';
    if (hasPoints) return '💰 포인트 할인';
    return '';
  }

  /// 이용내역 등 — 할인 종류 문구
  String get discountDetailLabel {
    final parts = <String>[];
    if (hasCoupon) parts.add('쿠폰 할인');
    if (hasPoints) parts.add('포인트 할인');
    return parts.join(' · ');
  }

  static ReservationPaymentPricing? fromPaymentOrderRow(
    Map<String, dynamic> row, {
    required int fallbackPrice,
  }) {
    final couponId = row['user_coupon_id']?.toString();
    final hasCoupon = couponId != null && couponId.isNotEmpty;
    final pointsUsed = (row['points_used'] as num?)?.toInt() ?? 0;
    final hasPoints = pointsUsed > 0;

    if (!hasCoupon && !hasPoints) return null;

    final total = (row['total_price'] as num?)?.toInt() ?? fallbackPrice;
    final original = (row['original_price'] as num?)?.toInt() ?? total;

    return ReservationPaymentPricing(
      originalPrice: original > 0 ? original : total,
      finalPrice: total,
      hasCoupon: hasCoupon,
      hasPoints: hasPoints,
    );
  }
}
