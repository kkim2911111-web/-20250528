import '../config/payment_config.dart';

class TossPaymentsLauncher {
  bool get isReady => false;

  Future<void> requestPayment({
    required String orderId,
    required String orderName,
    required int amount,
    required String customerKey,
    required TossPaymentMethod method,
    String? customerEmail,
    String? customerName,
  }) {
    throw UnsupportedError('토스페이먼츠는 Flutter Web에서만 지원합니다.');
  }

  String get origin => '';
}
