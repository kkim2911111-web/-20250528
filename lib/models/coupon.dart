/// 쿠폰 마스터 (coupons)
class CouponDefinition {
  final String id;
  final String title;
  final String? description;
  final String? discountLabel;
  final int discountAmount;
  final int minPaymentAmount;

  const CouponDefinition({
    required this.id,
    required this.title,
    this.description,
    this.discountLabel,
    this.discountAmount = 0,
    this.minPaymentAmount = 0,
  });

  factory CouponDefinition.fromMap(Map<String, dynamic> map) {
    final discountRaw = map['discount_amount'] ?? map['discount_value'];
    var discountAmount = (discountRaw as num?)?.toInt() ?? 0;
    if (discountAmount <= 0) {
      discountAmount = _parseAmountFromText(
        map['discount_label']?.toString() ??
            map['benefit_text']?.toString(),
      );
    }

    final minRaw = map['min_payment_amount'] ??
        map['minimum_payment_amount'] ??
        map['min_order_amount'];
    final minPaymentAmount = (minRaw as num?)?.toInt() ?? 0;

    return CouponDefinition(
      id: map['id'].toString(),
      title: (map['title'] ?? map['name'] ?? '쿠폰').toString(),
      description: map['description']?.toString(),
      discountLabel: (map['discount_label'] ??
              map['benefit_text'] ??
              (discountAmount > 0 ? discountAmount.toString() : null))
          ?.toString(),
      discountAmount: discountAmount,
      minPaymentAmount: minPaymentAmount,
    );
  }

  static int _parseAmountFromText(String? text) {
    if (text == null || text.isEmpty) return 0;
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0;
    return int.tryParse(digits) ?? 0;
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
  final bool isUsedFlag;

  const UserCoupon({
    required this.id,
    required this.userId,
    required this.couponId,
    this.coupon,
    this.status,
    this.expiresAt,
    this.usedAt,
    this.createdAt,
    this.isUsedFlag = false,
  });

  factory UserCoupon.fromMap(Map<String, dynamic> map) {
    final couponRaw = map['coupons'];
    CouponDefinition? coupon;
    if (couponRaw is Map) {
      coupon = CouponDefinition.fromMap(Map<String, dynamic>.from(couponRaw));
    }

    final isUsedFlag = map['is_used'] == true;

    return UserCoupon(
      id: map['id'].toString(),
      userId: map['user_id']?.toString() ?? '',
      couponId: map['coupon_id']?.toString() ?? '',
      coupon: coupon,
      status: map['status']?.toString(),
      expiresAt: _parseDate(map['expires_at'] ?? map['valid_until']),
      usedAt: _parseDate(map['used_at']),
      createdAt: _parseDate(map['created_at'] ?? map['issued_at']),
      isUsedFlag: isUsedFlag,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  bool get isUsed {
    if (isUsedFlag) return true;
    final s = status?.toLowerCase();
    if (s == 'used' || s == 'consumed') return true;
    if (usedAt != null) return true;
    return false;
  }

  int get discountAmount => coupon?.discountAmount ?? 0;

  int get minPaymentAmount => coupon?.minPaymentAmount ?? 0;

  bool canApplyToOrderAmount(int originalAmount) {
    if (!isAvailable) return false;
    if (discountAmount <= 0) return false;
    if (minPaymentAmount <= 0) return true;
    return originalAmount >= minPaymentAmount;
  }

  /// 만료일 00:00 기준 남은 일수 (당일=0, 지남=음수)
  int? get daysUntilExpiry {
    final end = expiresAt;
    if (end == null) return null;
    final today = DateTime.now();
    final endDate = DateTime(end.year, end.month, end.day);
    final todayDate = DateTime(today.year, today.month, today.day);
    return endDate.difference(todayDate).inDays;
  }

  bool get isExpiredByDate {
    final days = daysUntilExpiry;
    if (days == null) return false;
    return days < 0;
  }

  /// 기존 호환 — 시각 기준 만료
  bool get isExpired => isExpiredByDate;

  /// DB 자동 만료 처리 (status=expired 등)
  bool get isAutoExpired {
    final s = status?.toLowerCase().trim();
    return s == 'expired';
  }

  /// 쿠폰함 「만료됨」 탭
  bool get isCouponExpiredTab =>
      isExpiredByDate || (isUsed && isAutoExpired);

  /// 쿠폰함 「사용 완료」 탭 (예약 결제 등 실제 사용)
  bool get isCouponUsedTab => isUsed && !isCouponExpiredTab;

  /// 쿠폰함 「사용 가능」 탭
  bool get isCouponAvailableTab => !isUsed && !isExpiredByDate;

  bool get isExpiringWithin7Days {
    final days = daysUntilExpiry;
    return days != null && days >= 0 && days <= 7;
  }

  bool get isAvailable => isCouponAvailableTab;

  String get displayTitle => coupon?.title ?? '쿠폰';

  String? get displayBenefit => coupon?.discountLabel ?? coupon?.description;
}

/// 쿠폰 카드 유효기간 문구·색상
class CouponValidityDisplay {
  final String text;
  final CouponValidityTone tone;

  const CouponValidityDisplay({required this.text, required this.tone});

  static CouponValidityDisplay? forCoupon(
    UserCoupon coupon, {
    bool preferUsedDate = false,
  }) {
    if (preferUsedDate && coupon.usedAt != null) {
      final d = coupon.usedAt!;
      return CouponValidityDisplay(
        text: '사용일 ${_formatDate(d)}',
        tone: CouponValidityTone.muted,
      );
    }

    final expires = coupon.expiresAt;
    if (expires == null) return null;

    final days = coupon.daysUntilExpiry;
    if (days != null && days < 0) {
      return CouponValidityDisplay(
        text: '만료 ${_formatDate(expires)}',
        tone: CouponValidityTone.muted,
      );
    }
    if (days != null && days <= 7) {
      return CouponValidityDisplay(
        text: 'D-$days',
        tone: CouponValidityTone.urgentRed,
      );
    }
    if (days != null && days <= 30) {
      return CouponValidityDisplay(
        text: 'D-$days',
        tone: CouponValidityTone.urgentOrange,
      );
    }
    return CouponValidityDisplay(
      text: '~${_formatDate(expires)}',
      tone: CouponValidityTone.normal,
    );
  }

  static String _formatDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y.$m.$day';
  }
}

enum CouponValidityTone { normal, urgentOrange, urgentRed, muted }
