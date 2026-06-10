import 'package:danjicar_app/models/super_admin_models.dart';
import 'package:danjicar_app/utils/cancel_reason.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cancelReasonDisplayLabel', () {
    test('maps DB codes to Korean labels', () {
      expect(cancelReasonDisplayLabel('customer'), '고객취소');
      expect(cancelReasonDisplayLabel('admin_force'), '관리자취소');
      expect(cancelReasonDisplayLabel('blacklist_auto'), '블랙리스트');
      expect(cancelReasonDisplayLabel('payment_failed'), '결제실패');
    });

    test('NULL or empty → 취소 only', () {
      expect(cancelReasonDisplayLabel(null), '취소');
      expect(cancelReasonDisplayLabel(''), '취소');
    });

    test('passes through server Korean labels', () {
      expect(cancelReasonDisplayLabel('고객취소'), '고객취소');
      expect(cancelReasonDisplayLabel('관리자취소'), '관리자취소');
    });
  });

  group('SuperAdminSettlementCancelItem', () {
    test('parses cancel_reason codes via display label', () {
      final customer = SuperAdminSettlementCancelItem.fromMap({
        'reservation_id': 'r1',
        'renter_name': '홍길동',
        'cancel_reason': 'customer',
      });
      expect(customer.cancelReason, '고객취소');

      final admin = SuperAdminSettlementCancelItem.fromMap({
        'reservation_id': 'r2',
        'renter_name': '김철수',
        'cancel_reason': 'admin_force',
      });
      expect(admin.cancelReason, '관리자취소');

      final blacklist = SuperAdminSettlementCancelItem.fromMap({
        'reservation_id': 'r3',
        'renter_name': '이영희',
        'cancel_reason': 'blacklist_auto',
      });
      expect(blacklist.cancelReason, '블랙리스트');

      final payment = SuperAdminSettlementCancelItem.fromMap({
        'reservation_id': 'r4',
        'renter_name': '박민수',
        'cancel_reason': 'payment_failed',
      });
      expect(payment.cancelReason, '결제실패');
    });

    test('missing cancel_reason → 취소 only', () {
      final item = SuperAdminSettlementCancelItem.fromMap({
        'reservation_id': 'r9',
        'renter_name': '미상',
      });
      expect(item.cancelReason, '취소');
    });

    test('server pre-localized label preserved', () {
      final item = SuperAdminSettlementCancelItem.fromMap({
        'reservation_id': 'r5',
        'renter_name': '테스트',
        'cancel_reason': '고객취소',
      });
      expect(item.cancelReason, '고객취소');
    });
  });
}
