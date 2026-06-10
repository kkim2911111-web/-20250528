import 'package:intl/intl.dart';

import '../utils/rental_pricing.dart';

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
