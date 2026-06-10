import 'package:danjicar_app/models/super_admin_models.dart';
import 'package:danjicar_app/widgets/settlement_detail_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SuperAdminSettlementSheet parses payment and cancel items', () {
    final sheet = SuperAdminSettlementSheet.fromRpc({
      'payment_count': 2,
      'cancel_count': 1,
      'rental_count': 3,
      'items': [
        {
          'reservation_id': 'r1',
          'renter_name': '홍길동',
          'total_price': 10000,
        },
      ],
      'payment_items': [
        {
          'order_id': 'o1',
          'reservation_id': 'r1',
          'renter_name': '홍길동',
          'paid_at': '2026-06-15T10:00:00Z',
          'payment_amount': 10000,
        },
        {
          'order_id': 'o2',
          'reservation_id': 'r2',
          'renter_name': '김철수',
          'paid_at': '2026-06-20T10:00:00Z',
          'payment_amount': 20000,
        },
      ],
      'cancel_items': [
        {
          'reservation_id': 'r9',
          'renter_name': '이영희',
          'cancelled_at': '2026-06-10T12:00:00Z',
          'paid_amount': 15000,
          'refund_amount': 15000,
          'cancel_reason': '고객취소',
        },
      ],
    });

    expect(sheet.paymentItems.length, 2);
    expect(sheet.cancelItems.length, 1);
    expect(sheet.paymentCount, 2);
    expect(sheet.cancelCount, 1);
    expect(sheet.rentalCount, 3);
    expect(sheet.cancelItems.first.refundAmount, 15000);
    expect(sheet.cancelItems.first.cancelReason, '고객취소');
  });

  test('SettlementDetailTab titles', () {
    expect(
      SettlementDetailTab.rental.title(2026, 6),
      '완료 예약 상세 · 2026년 6월',
    );
    expect(
      SettlementDetailTab.payment.title(2026, 6),
      '결제 내역 · 2026년 6월',
    );
    expect(
      SettlementDetailTab.cancel.title(2026, 6),
      '취소 내역 · 2026년 6월',
    );
  });
}
