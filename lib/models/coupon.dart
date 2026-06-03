/// 쿠폰 마스터 (coupons)
class CouponDefinition {
  final String id;
  final String title;
  final String? description;
  final String? discountLabel;

  const CouponDefinition({
    required this.id,
    required this.title,
    this.description,
    this.discountLabel,
  });

  factory CouponDefinition.fromMap(Map<String, dynamic> map) {
    return CouponDefinition(
      id: map['id'].toString(),
      title: (map['title'] ?? map['name'] ?? '쿠폰').toString(),
      description: map['description']?.toString(),
      discountLabel: (map['discount_label'] ??
              map['benefit_text'] ??
              map['discount_amount'])
          ?.toString(),
    );
  }
}

/// 보유 쿠폰 (user_coupons + coupons 조인)
class UserCoupon {
  final String id;
  final String userId;
  final String couponId;
  final CouponDefinition? coupon;
  final String? status;
  final DateTime? expiresAt;
  final DateTime? usedAt;
  final DateTime? createdAt;

  const UserCoupon({
    required this.id,
    required this.userId,
    required this.couponId,
    this.coupon,
    this.status,
    this.expiresAt,
    this.usedAt,
    this.createdAt,
  });

  factory UserCoupon.fromMap(Map<String, dynamic> map) {
    final couponRaw = map['coupons'];
    CouponDefinition? coupon;
    if (couponRaw is Map) {
      coupon = CouponDefinition.fromMap(Map<String, dynamic>.from(couponRaw));
    }

    return UserCoupon(
      id: map['id'].toString(),
      userId: map['user_id']?.toString() ?? '',
      couponId: map['coupon_id']?.toString() ?? '',
      coupon: coupon,
      status: map['status']?.toString(),
      expiresAt: _parseDate(map['expires_at'] ?? map['valid_until']),
      usedAt: _parseDate(map['used_at']),
      createdAt: _parseDate(map['created_at'] ?? map['issued_at']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  bool get isUsed {
    final s = status?.toLowerCase();
    if (s == 'used' || s == 'consumed') return true;
    if (usedAt != null) return true;
    return false;
  }

  bool get isExpired {
    final end = expiresAt;
    if (end == null) return false;
    return DateTime.now().isAfter(end);
  }

  bool get isAvailable => !isUsed && !isExpired;

  String get displayTitle => coupon?.title ?? '쿠폰';

  String? get displayBenefit => coupon?.discountLabel ?? coupon?.description;
}
