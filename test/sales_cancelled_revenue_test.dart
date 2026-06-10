import 'package:danjicar_app/models/super_admin_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// `sales_completed_reservations_v` 고객취소 잔여매출 규칙 — gross = max(paid - refund, 0)
int cancelledCustomerGross({
  required int paidAmount,
  required int refundAmount,
}) {
  final net = paidAmount - refundAmount;
  return net > 0 ? net : 0;
}

void main() {
  group('cancelled customer sales gross', () {
    test('0% refund → full paid amount is revenue', () {
      expect(
        cancelledCustomerGross(paidAmount: 20000, refundAmount: 0),
        20000,
      );
    });

    test('50% refund → half remains as revenue', () {
      expect(
        cancelledCustomerGross(paidAmount: 15000, refundAmount: 7500),
        7500,
      );
    });

    test('100% refund → excluded from sales (gross 0)', () {
      expect(
        cancelledCustomerGross(paidAmount: 10000, refundAmount: 10000),
        0,
      );
    });
  });

  group('settlement cancel list with zero refund', () {
    test('cancel_items shows refund_amount 0 for no-refund cancel', () {
      final sheet = SuperAdminSettlementSheet.fromRpc({
        'total_paid': 20000,
        'net_revenue': 20000,
        'cancel_refund': 0,
        'cancel_count': 1,
        'rental_count': 1,
        'payment_count': 1,
        'items': [
          {
            'reservation_id': 'r-cancel',
            'renter_name': '홍길동',
            'total_price': 20000,
          },
        ],
        'cancel_items': [
          {
            'reservation_id': 'r-cancel',
            'renter_name': '홍길동',
            'cancelled_at': '2026-06-10T12:00:00Z',
            'paid_amount': 20000,
            'refund_amount': 0,
            'cancel_reason': '고객취소',
          },
        ],
      });

      expect(sheet.cancelItems.first.refundAmount, 0);
      expect(sheet.cancelItems.first.paidAmount, 20000);
      expect(sheet.totalPaid, 20000);
      expect(sheet.netRevenue, 20000);
      expect(sheet.rentalCount, 1);
    });

    test('50% partial cancel — rental gross matches paid minus refund', () {
      const paid = 15000;
      const refund = 7500;
      final gross = cancelledCustomerGross(
        paidAmount: paid,
        refundAmount: refund,
      );

      final sheet = SuperAdminSettlementSheet.fromRpc({
        'total_paid': gross,
        'net_revenue': gross,
        'cancel_refund': refund,
        'cancel_count': 1,
        'rental_count': 1,
        'payment_count': 0,
        'items': [
          {
            'reservation_id': 'r-half',
            'renter_name': '김철수',
            'total_price': gross,
          },
        ],
        'cancel_items': [
          {
            'reservation_id': 'r-half',
            'renter_name': '김철수',
            'paid_amount': paid,
            'refund_amount': refund,
            'cancel_reason': '고객취소',
          },
        ],
      });

      expect(gross, 7500);
      expect(sheet.totalPaid, 7500);
      expect(sheet.cancelItems.first.refundAmount, refund);
    });
  });
}
