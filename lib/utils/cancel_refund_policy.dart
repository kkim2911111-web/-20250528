import 'package:intl/intl.dart';

import '../utils/rental_pricing.dart';

/// 취소·환불 정책 UI 문구 (FAQ 단일 출처)
abstract final class CancelRefundDisplay {
  static const faqCancelQuestion = '예약 취소는 언제까지 가능한가요?';

  static const faqCancelAnswer =
      '대여 시작 전까지 언제든 취소할 수 있습니다.\n'
      '· 카셰어링(시간): 출고 1시간 전까지 전액 환불, 이후 환불 없음\n'
      '· 일·월 렌트: 출고 3일(72시간) 전 전액 / '
      '1~3일(24~72시간) 전 50% / 1일(24시간) 이내 환불 없음\n'
      '· 전액 환불 시 사용한 쿠폰·포인트가 복구됩니다\n'
      '· 환불 없는 구간에서도 취소 시 차량 예약은 해제됩니다';

  static const waitingGuidePrefix = '출고 전 언제든 취소 가능 · ';
  static const waitingGuideLink = '환불 규정 보기 >';

  static String refundTierLabel({
    required RentalType? rentalType,
    required double refundRate,
  }) {
    final type = rentalType ?? RentalType.hourly;
    if (type == RentalType.hourly) {
      if (refundRate >= 1) return '출고 1시간 전 취소 — 전액 환불';
      return '출고 1시간 이내 취소 — 환불 없음';
    }
    if (refundRate >= 1) return '출고 3일(72시간) 전 취소 — 전액 환불';
    if (refundRate >= 0.5) return '출고 1~3일(24~72시간) 전 취소 — 50% 환불';
    return '출고 1일(24시간) 이내 취소 — 환불 없음';
  }
}

/// 서버 `calc_cancel_refund_rate` / `preview_cancel_refund_for_me` 와 동일한 규칙.
class CancelRefundPolicy {
  static double refundRate({
    required RentalType? rentalType,
    required DateTime startAt,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final hours = startAt.difference(at).inMicroseconds / 3600000000.0;
    final type = rentalType ?? RentalType.hourly;

    if (type == RentalType.daily || type == RentalType.monthly) {
      if (hours >= 72) return 1;
      if (hours >= 24) return 0.5;
      return 0;
    }

    if (hours >= 1) return 1;
    return 0;
  }

  static int refundAmount({
    required RentalType? rentalType,
    required DateTime startAt,
    required int paidAmount,
    DateTime? now,
  }) {
    final rate = refundRate(
      rentalType: rentalType,
      startAt: startAt,
      now: now,
    );
    if (paidAmount <= 0 || rate <= 0) return 0;
    return (paidAmount * rate).floor();
  }

  static int refundPercent({
    required RentalType? rentalType,
    required DateTime startAt,
    DateTime? now,
  }) {
    return (refundRate(
          rentalType: rentalType,
          startAt: startAt,
          now: now,
        ) *
            100)
        .round();
  }

  static bool shouldRestoreBenefits({
    required RentalType? rentalType,
    required DateTime startAt,
    required int paidAmount,
    DateTime? now,
  }) {
    if (paidAmount <= 0) return true;
    return refundRate(
          rentalType: rentalType,
          startAt: startAt,
          now: now,
        ) >=
        1;
  }
}

class CancelRefundQuote {
  final String reservationId;
  final RentalType? rentalType;
  final int paidAmount;
  final double refundRate;
  final int refundAmount;
  final int refundPercent;
  final bool restoreBenefits;

  const CancelRefundQuote({
    required this.reservationId,
    this.rentalType,
    required this.paidAmount,
    required this.refundRate,
    required this.refundAmount,
    required this.refundPercent,
    required this.restoreBenefits,
  });

  factory CancelRefundQuote.fromRpc(Map<String, dynamic> map) {
    final rate = (map['refundRate'] as num?)?.toDouble() ?? 0;
    return CancelRefundQuote(
      reservationId: map['reservationId']?.toString() ?? '',
      rentalType: RentalType.fromDb(map['rentalType']?.toString()),
      paidAmount: (map['paidAmount'] as num?)?.toInt() ?? 0,
      refundRate: rate,
      refundAmount: (map['refundAmount'] as num?)?.toInt() ?? 0,
      refundPercent:
          (map['refundPercent'] as num?)?.toInt() ?? (rate * 100).round(),
      restoreBenefits: map['restoreBenefits'] == true,
    );
  }

  factory CancelRefundQuote.fromReservation({
    required String reservationId,
    required DateTime? startAt,
    required int paidAmount,
    RentalType? rentalType,
    DateTime? now,
  }) {
    if (startAt == null) {
      return CancelRefundQuote(
        reservationId: reservationId,
        rentalType: rentalType,
        paidAmount: paidAmount,
        refundRate: 0,
        refundAmount: 0,
        refundPercent: 0,
        restoreBenefits: paidAmount <= 0,
      );
    }

    final rate = CancelRefundPolicy.refundRate(
      rentalType: rentalType,
      startAt: startAt,
      now: now,
    );
    final refund = CancelRefundPolicy.refundAmount(
      rentalType: rentalType,
      startAt: startAt,
      paidAmount: paidAmount,
      now: now,
    );

    return CancelRefundQuote(
      reservationId: reservationId,
      rentalType: rentalType,
      paidAmount: paidAmount,
      refundRate: rate,
      refundAmount: refund,
      refundPercent: (rate * 100).round(),
      restoreBenefits: CancelRefundPolicy.shouldRestoreBenefits(
        rentalType: rentalType,
        startAt: startAt,
        paidAmount: paidAmount,
        now: now,
      ),
    );
  }

  bool get isNoRefund => refundAmount <= 0 && paidAmount > 0;

  bool get isPartialRefund =>
      refundAmount > 0 && paidAmount > 0 && refundAmount < paidAmount;

  String get refundTierLabel => CancelRefundDisplay.refundTierLabel(
        rentalType: rentalType,
        refundRate: refundRate,
      );

  String confirmMessage({NumberFormat? won}) {
    final formatter = won ?? NumberFormat('#,###');
    if (paidAmount <= 0) {
      return '결제 금액이 없습니다. 예약을 취소하시겠습니까?';
    }
    if (isNoRefund) {
      return '환불 불가 시점입니다. 취소하시겠습니까?';
    }
    if (refundPercent == 100) {
      return '지금 취소 시 환불 ₩${formatter.format(refundAmount)} (전액)\n'
          '정말 취소하시겠습니까?';
    }
    return '지금 취소 시 환불 ₩${formatter.format(refundAmount)} ($refundPercent%)\n'
        '정말 취소하시겠습니까?';
  }
}
