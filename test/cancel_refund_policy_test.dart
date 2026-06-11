import 'package:danjicar_app/utils/cancel_refund_policy.dart';
import 'package:danjicar_app/utils/rental_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime.utc(2026, 6, 15, 10, 0);

  group('CancelRefundPolicy.hourly', () {
    test('exactly 1 hour before → 100%', () {
      final now = start.subtract(const Duration(hours: 1));
      expect(
        CancelRefundPolicy.refundRate(
          rentalType: RentalType.hourly,
          startAt: start,
          now: now,
        ),
        1,
      );
      expect(
        CancelRefundPolicy.refundAmount(
          rentalType: RentalType.hourly,
          startAt: start,
          paidAmount: 10000,
          now: now,
        ),
        10000,
      );
    });

    test('59 minutes before → 0%', () {
      final now = start.subtract(const Duration(minutes: 59));
      expect(
        CancelRefundPolicy.refundRate(
          rentalType: RentalType.hourly,
          startAt: start,
          now: now,
        ),
        0,
      );
      expect(
        CancelRefundPolicy.refundAmount(
          rentalType: RentalType.hourly,
          startAt: start,
          paidAmount: 10000,
          now: now,
        ),
        0,
      );
    });
  });

  group('CancelRefundPolicy.daily', () {
    test('exactly 72 hours before → 100%', () {
      final now = start.subtract(const Duration(hours: 72));
      expect(
        CancelRefundPolicy.refundRate(
          rentalType: RentalType.daily,
          startAt: start,
          now: now,
        ),
        1,
      );
    });

    test('exactly 24 hours before → 50%', () {
      final now = start.subtract(const Duration(hours: 24));
      expect(
        CancelRefundPolicy.refundRate(
          rentalType: RentalType.daily,
          startAt: start,
          now: now,
        ),
        0.5,
      );
      expect(
        CancelRefundPolicy.refundAmount(
          rentalType: RentalType.daily,
          startAt: start,
          paidAmount: 15000,
          now: now,
        ),
        7500,
      );
    });

    test('23 hours before → 0%', () {
      final now = start.subtract(const Duration(hours: 23));
      expect(
        CancelRefundPolicy.refundRate(
          rentalType: RentalType.daily,
          startAt: start,
          now: now,
        ),
        0,
      );
    });

    test('71 hours before → 50%', () {
      final now = start.subtract(const Duration(hours: 71));
      expect(
        CancelRefundPolicy.refundRate(
          rentalType: RentalType.daily,
          startAt: start,
          now: now,
        ),
        0.5,
      );
    });
  });

  group('CancelRefundPolicy.monthly', () {
    test('uses same tiers as daily', () {
      final now = start.subtract(const Duration(hours: 48));
      expect(
        CancelRefundPolicy.refundRate(
          rentalType: RentalType.monthly,
          startAt: start,
          now: now,
        ),
        0.5,
      );
    });
  });

  group('benefit restore', () {
    test('100% refund restores benefits', () {
      final now = start.subtract(const Duration(hours: 2));
      expect(
        CancelRefundPolicy.shouldRestoreBenefits(
          rentalType: RentalType.hourly,
          startAt: start,
          paidAmount: 5000,
          now: now,
        ),
        isTrue,
      );
    });

    test('0% refund does not restore benefits', () {
      final now = start.subtract(const Duration(minutes: 30));
      expect(
        CancelRefundPolicy.shouldRestoreBenefits(
          rentalType: RentalType.hourly,
          startAt: start,
          paidAmount: 5000,
          now: now,
        ),
        isFalse,
      );
    });

    test('50% refund does not restore benefits', () {
      final now = start.subtract(const Duration(hours: 30));
      expect(
        CancelRefundPolicy.shouldRestoreBenefits(
          rentalType: RentalType.daily,
          startAt: start,
          paidAmount: 10000,
          now: now,
        ),
        isFalse,
      );
    });

    test('zero paid amount always restores', () {
      expect(
        CancelRefundPolicy.shouldRestoreBenefits(
          rentalType: RentalType.hourly,
          startAt: start,
          paidAmount: 0,
          now: start,
        ),
        isTrue,
      );
    });
  });

  group('CancelRefundQuote.refundTierLabel', () {
    test('daily 100% tier', () {
      final quote = CancelRefundQuote(
        reservationId: 'r1',
        rentalType: RentalType.daily,
        paidAmount: 10000,
        refundRate: 1,
        refundAmount: 10000,
        refundPercent: 100,
        restoreBenefits: true,
      );
      expect(quote.refundTierLabel, '출고 3일(72시간) 전 취소 — 전액 환불');
    });

    test('hourly no-refund tier', () {
      final quote = CancelRefundQuote(
        reservationId: 'r1',
        rentalType: RentalType.hourly,
        paidAmount: 10000,
        refundRate: 0,
        refundAmount: 0,
        refundPercent: 0,
        restoreBenefits: false,
      );
      expect(quote.refundTierLabel, '출고 1시간 이내 취소 — 환불 없음');
    });
  });

  group('CancelRefundQuote.confirmMessage', () {
    test('0% shows no-refund prompt', () {
      final quote = CancelRefundQuote(
        reservationId: 'r1',
        paidAmount: 10000,
        refundRate: 0,
        refundAmount: 0,
        refundPercent: 0,
        restoreBenefits: false,
      );
      expect(quote.confirmMessage(), contains('환불 불가'));
    });

    test('50% shows partial refund amount', () {
      final quote = CancelRefundQuote(
        reservationId: 'r1',
        paidAmount: 15000,
        refundRate: 0.5,
        refundAmount: 7500,
        refundPercent: 50,
        restoreBenefits: false,
      );
      expect(quote.confirmMessage(), contains('7,500'));
      expect(quote.confirmMessage(), contains('50%'));
    });
  });
}
