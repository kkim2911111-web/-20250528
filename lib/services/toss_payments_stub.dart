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
    throw UnsupportedError(
      '토스페이먼츠는 이 플랫폼에서 지원되지 않습니다.',
    );
  }

  Future<void> requestBillingAuth({
    required String customerKey,
    String? customerEmail,
    String? customerName,
  }) {
    throw UnsupportedError(
      '토스페이먼츠는 이 플랫폼에서 지원되지 않습니다.',
    );
  }

  String get origin => '';
}
