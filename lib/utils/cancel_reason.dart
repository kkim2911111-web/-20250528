/// DB reservations.cancel_reason 코드
abstract final class CancelReasonCode {
  static const customer = 'customer';
  static const adminForce = 'admin_force';
  static const blacklistAuto = 'blacklist_auto';
  static const paymentFailed = 'payment_failed';
  static const vehicleNotReturned = 'vehicle_not_returned';
}

bool isVehicleNotReturnedCancelReason(String? raw) =>
    raw?.trim() == CancelReasonCode.vehicleNotReturned;

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
    case CancelReasonCode.vehicleNotReturned:
    case '차량미회수':
      return '차량미회수';
    case null:
    case '':
      return '취소';
    default:
      return raw!;
  }
}

/// 이용내역·예약 카드 상태 뱃지 (차량미회수 전액환불)
const vehicleNotReturnedStatusBadgeLabel = '이용불가 환불';
