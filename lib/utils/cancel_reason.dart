/// DB reservations.cancel_reason 코드
abstract final class CancelReasonCode {
  static const customer = 'customer';
  static const adminForce = 'admin_force';
  static const blacklistAuto = 'blacklist_auto';
  static const paymentFailed = 'payment_failed';
}

/// 정산·UI 표시 라벨 (서버 cancel_reason_display_label 과 동일)
String cancelReasonDisplayLabel(String? raw) {
  switch (raw?.trim()) {
    case CancelReasonCode.customer:
    case '고객취소':
      return '고객취소';
    case CancelReasonCode.adminForce:
    case '관리자취소':
    case '관리자 강제취소':
      return '관리자취소';
    case CancelReasonCode.blacklistAuto:
    case '블랙리스트':
      return '블랙리스트';
    case CancelReasonCode.paymentFailed:
    case '결제실패':
      return '결제실패';
    case null:
    case '':
      return '취소';
    default:
      return raw!;
  }
}
