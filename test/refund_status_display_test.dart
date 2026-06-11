import 'package:danjicar_app/utils/refund_status_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('refundBadgeKind classifies partial and full refund', () {
    expect(
      refundBadgeKind(paidAmount: 210000, refundAmount: 105000),
      RefundBadgeKind.partial,
    );
    expect(
      refundBadgeKind(paidAmount: 210000, refundAmount: 210000),
      RefundBadgeKind.full,
    );
    expect(
      refundBadgeKind(paidAmount: 210000, refundAmount: 0),
      RefundBadgeKind.none,
    );
    expect(
      refundBadgeKind(paidAmount: 0, refundAmount: 105000),
      RefundBadgeKind.none,
    );
  });
}
