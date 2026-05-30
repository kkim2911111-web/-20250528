/// payment_orders.status — DB check 허용값: pending | paid | failed | cancelled
class PaymentOrderStatus {
  PaymentOrderStatus._();

  static const pending = 'pending';
  static const paid = 'paid';
  static const failed = 'failed';
  static const cancelled = 'cancelled';

  /// 구 add_payment_orders_confirmed_status.sql 마이그레이션 데이터 (읽기 전용)
  static const legacyConfirmed = 'confirmed';

  static bool isPaid(String? status) {
    final s = status ?? '';
    return s == paid || s == legacyConfirmed;
  }

  static bool isCancellable(String? status) {
    final s = status ?? '';
    return s == pending || s == failed;
  }
}
