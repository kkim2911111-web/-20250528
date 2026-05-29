/// 결제 성공 콜백 결과 — reservations 저장 완료
class PaymentConfirmResult {
  final String reservationId;
  final String orderId;
  final String paymentKey;
  final int? totalPrice;
  final String? vehicleName;
  final bool alreadyPaid;

  const PaymentConfirmResult({
    required this.reservationId,
    required this.orderId,
    required this.paymentKey,
    this.totalPrice,
    this.vehicleName,
    this.alreadyPaid = false,
  });

  factory PaymentConfirmResult.fromMap(Map<String, dynamic> map) {
    return PaymentConfirmResult(
      reservationId: map['reservationId']?.toString() ??
          map['reservation_id']?.toString() ??
          '',
      orderId: map['orderId']?.toString() ?? '',
      paymentKey: map['paymentKey']?.toString() ?? '',
      totalPrice: (map['totalPrice'] as num?)?.toInt(),
      vehicleName: map['vehicleName']?.toString(),
      alreadyPaid: map['alreadyPaid'] == true,
    );
  }
}
