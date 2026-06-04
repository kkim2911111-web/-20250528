/// payment_orders 테이블 스키마 (Supabase 실제 구조 기준)
class PaymentOrderColumns {
  PaymentOrderColumns._();

  static const selectSummary =
      'order_id, status, payment_key, has_payment_key, reservation_id, total_price, '
      'user_coupon_id, points_used';

  static const selectDetail =
      'id, order_id, user_id, vehicle_id, vehicle_name, start_time, end_time, '
      'total_price, status, payment_key, has_payment_key, reservation_id, '
      'created_at, updated_at';

  /// insert 시 명시하는 컬럼 (id/created_at/updated_at/has_payment_key는 DB default)
  static const insertFields = [
    'order_id',
    'user_id',
    'vehicle_id',
    'vehicle_name',
    'start_time',
    'end_time',
    'total_price',
    'status',
  ];
}

/// payment_orders.status — payment_orders_status_check 허용값
class PaymentOrderStatus {
  PaymentOrderStatus._();

  static const pending = 'pending';
  static const paid = 'paid';
  static const failed = 'failed';
  static const cancelled = 'cancelled';

  /// DB 제약에 없음 — 구 데이터 읽기 전용
  static const legacyConfirmed = 'confirmed';

  static const allowed = [pending, paid, failed, cancelled];

  static bool isPaid(String? status) {
    final s = status ?? '';
    return s == paid || s == legacyConfirmed;
  }

  static bool isCancellable(String? status) {
    final s = status ?? '';
    return s == pending || s == failed;
  }

  static bool isValid(String? status) {
    final s = status ?? '';
    return allowed.contains(s) || s == legacyConfirmed;
  }
}

/// payment_orders update/insert payload (타입·컬럼명 DB 일치)
class PaymentOrderPayload {
  PaymentOrderPayload._();

  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  static bool isUuid(String? value) {
    if (value == null || value.isEmpty) return false;
    return RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(value);
  }

  static Map<String, dynamic> insertPending({
    required String orderId,
    required String userId,
    required String vehicleId,
    required String? vehicleName,
    required String startTimeIso,
    required String endTimeIso,
    required int totalPrice,
  }) {
    return {
      'order_id': orderId,
      'user_id': userId,
      'vehicle_id': vehicleId,
      'vehicle_name': vehicleName,
      'start_time': startTimeIso,
      'end_time': endTimeIso,
      'total_price': totalPrice,
      'status': PaymentOrderStatus.pending,
    };
  }

  static Map<String, dynamic> markPaid({
    required String paymentKey,
    String? reservationId,
  }) {
    return {
      'status': PaymentOrderStatus.paid,
      'payment_key': paymentKey,
      'has_payment_key': paymentKey.isNotEmpty,
      'updated_at': _nowIso(),
      if (reservationId != null && isUuid(reservationId))
        'reservation_id': reservationId,
    };
  }

  static Map<String, dynamic> markCancelled() => {
        'status': PaymentOrderStatus.cancelled,
        'updated_at': _nowIso(),
      };

  static Map<String, dynamic> markFailed() => {
        'status': PaymentOrderStatus.failed,
        'updated_at': _nowIso(),
      };
}
